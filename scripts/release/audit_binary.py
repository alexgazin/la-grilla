#!/usr/bin/env python3
"""Audit the actual thin arm64 iPhone Mach-O with Python's standard library.

FoundationModels is iOS 26-only while the app supports iOS 18. The framework
load command AND symbol/chained imports must stay weak; SDK compilation alone
cannot verify that an older OS can load the executable. This is a static gate,
not a replacement for launching the signed app on iOS 18.
"""
import argparse
import json
import pathlib
import struct
import sys
import uuid

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
DYLIB_COMMANDS = {LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, 0x8000001F, 0x80000023, 0x20}
FOUNDATION_MODELS = '/System/Library/Frameworks/FoundationModels.framework/FoundationModels'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bounds(data, offset, size, context):
    require(offset >= 0 and size >= 0 and offset <= len(data) and size <= len(data) - offset,
            'Truncated/out-of-range ' + context)


def cstring(data, offset, end, context):
    require(0 <= offset < end <= len(data), 'Invalid string bounds: ' + context)
    terminator = data.find(b'\0', offset, end)
    require(terminator >= 0, 'Unterminated string: ' + context)
    return data[offset:terminator].decode('utf-8', errors='strict')


def version(value):
    return f'{value >> 16}.{(value >> 8) & 255}.{value & 255}'


class MachO:
    def __init__(self, data):
        bounds(data, 0, 32, 'Mach-O header')
        magic, cpu, subtype, kind, count, command_bytes, flags, reserved = struct.unpack_from('<IiiIIIII', data)
        require(magic == MH_MAGIC_64, 'Expected a thin little-endian 64-bit Mach-O; FAT/other formats are not supported')
        require(cpu == CPU_TYPE_ARM64 and subtype == 0, 'Expected the arm64 iPhone architecture')
        require(count <= 4096, 'Unreasonable load-command count')
        bounds(data, 32, command_bytes, 'load commands')
        self.data, self.kind, self.commands, self.dylibs, self.sections = data, kind, [], [], []
        self.binary_uuid = None
        position, end = 32, 32 + command_bytes
        for _ in range(count):
            require(position + 8 <= end, 'Truncated load-command header')
            command, size = struct.unpack_from('<II', data, position)
            require(size >= 8 and size % 8 == 0 and size <= end - position, 'Invalid load-command size')
            self.commands.append((command, position, size))
            if command in DYLIB_COMMANDS:
                require(size >= 24, 'Truncated dylib command')
                name_offset = struct.unpack_from('<I', data, position + 8)[0]
                require(name_offset >= 24, 'Invalid dylib name offset')
                self.dylibs.append((command, cstring(data, position + name_offset, position + size, 'dylib name')))
            elif command == 0x1B:
                require(size == 24 and self.binary_uuid is None, 'Invalid/duplicate LC_UUID')
                self.binary_uuid = str(uuid.UUID(bytes=bytes(data[position + 8:position + 24]))).upper()
            elif command == 0x19:
                require(size >= 72, 'Truncated LC_SEGMENT_64')
                section_count = struct.unpack_from('<I', data, position + 64)[0]
                require(section_count <= (size - 72) // 80, 'Truncated segment sections')
                for index in range(section_count):
                    entry = position + 72 + index * 80
                    section_name, segment_name, address, length, offset, align, reloc, relocs, section_flags, r1, r2, r3 = struct.unpack_from('<16s16sQQIIIIIIII', data, entry)
                    self.sections.append({'name': section_name.split(b'\0')[0].decode(),
                                          'segment': segment_name.split(b'\0')[0].decode(),
                                          'address': address, 'size': length, 'offset': offset, 'flags': section_flags})
            position += size
        require(position == end, 'Load-command count/size mismatch')
        require(self.binary_uuid is not None, 'Missing LC_UUID')

    def only_command(self, kind, minimum):
        matches = [(offset, size) for command, offset, size in self.commands if command == kind]
        require(len(matches) == 1 and matches[0][1] >= minimum, f'Missing/invalid/duplicate load command {kind:#x}')
        return matches[0][0]

    def symbols(self):
        position = self.only_command(2, 24)
        symbol_offset, symbol_count, strings_offset, strings_size = struct.unpack_from('<IIII', self.data, position + 8)
        require(symbol_count <= 1_000_000, 'Unreasonable symbol count')
        bounds(self.data, symbol_offset, symbol_count * 16, 'symbol table')
        bounds(self.data, strings_offset, strings_size, 'symbol strings')
        for index in range(symbol_count):
            offset = symbol_offset + index * 16
            name_offset, kind, section, description, value = struct.unpack_from('<IBBHQ', self.data, offset)
            require(name_offset < strings_size, 'Invalid symbol name offset')
            name = cstring(self.data, strings_offset + name_offset, strings_offset + strings_size, 'symbol name')
            yield name, kind, section, description, value, offset


def audit_binary(data, dsym_data=None):
    image = MachO(data)
    require(image.kind == 2, 'Expected MH_EXECUTE application binary')
    build = image.only_command(0x32, 24)
    platform, minimum, sdk, tool_count = struct.unpack_from('<IIII', data, build + 8)
    require(platform == 2, 'Expected PLATFORM_IOS, not Simulator/macOS')
    require(minimum == (18 << 16), f'Deployment target drift: expected iOS 18.0.0, found {version(minimum)}')
    require(sdk >= (26 << 16), 'App Store archive requires iOS SDK 26 or later')
    model_dylibs = [(index + 1, command, name) for index, (command, name) in enumerate(image.dylibs)
                    if 'FoundationModels.framework/' in name]
    require(len(model_dylibs) == 1, 'Expected exactly one FoundationModels dependency')
    ordinal, command, name = model_dylibs[0]
    require(name == FOUNDATION_MODELS and command == LC_LOAD_WEAK_DYLIB,
            'FoundationModels must use LC_LOAD_WEAK_DYLIB for iOS 18 startup')
    model_symbols = []
    for name, kind, section, description, value, offset in image.symbols():
        if kind & 0xE0 or kind & 0x0E != 0:
            continue
        library = description >> 8
        if library == ordinal or 'FoundationModels' in name:
            require(library == ordinal, 'FoundationModels symbol has an unexpected library ordinal: ' + name)
            require(description & 0x40, 'FoundationModels import is not N_WEAK_REF: ' + name)
            model_symbols.append(name)
    require(model_symbols, 'Expected FoundationModels imports in this release build')
    # Modern Xcode also records binding in dyld chained fixups. Check those
    # actual loader imports, rather than trusting symbol-table annotations alone.
    fixups = image.only_command(0x80000034, 16)
    offset, size = struct.unpack_from('<II', data, fixups + 8)
    bounds(data, offset, size, 'dyld chained fixups')
    require(size >= 28, 'Truncated chained-fixups header')
    fixup_version, starts, imports, strings, count, format_id, strings_format = struct.unpack_from('<7I', data, offset)
    require(fixup_version == 0 and strings_format == 0, 'Unsupported chained-fixups/symbols format')
    stride = {1: 4, 2: 8, 3: 16}.get(format_id)
    require(stride is not None, 'Unsupported chained-import format')
    require(imports <= size and count <= (size - imports) // stride and strings < size, 'Invalid chained-import bounds')
    weak_bindings = []
    for index in range(count):
        entry = offset + imports + index * stride
        if format_id in (1, 2):
            value = struct.unpack_from('<I', data, entry)[0]
            library, weak, name_offset = value & 255, (value >> 8) & 1, value >> 9
        else:
            value = struct.unpack_from('<Q', data, entry)[0]
            library, weak, name_offset = value & 65535, (value >> 16) & 1, value >> 32
        symbol = cstring(data, offset + strings + name_offset, offset + size, 'chained-import name')
        if library == ordinal or 'FoundationModels' in symbol:
            require(library == ordinal and weak == 1, 'FoundationModels dyld binding is not weak: ' + symbol)
            weak_bindings.append(symbol)
    require(weak_bindings, 'Expected FoundationModels chained imports')
    require(set(weak_bindings) == set(model_symbols), 'FoundationModels symbol-table/chained-import mismatch')
    if dsym_data is not None:
        dsym = MachO(dsym_data)
        require(dsym.kind == 10 and dsym.binary_uuid == image.binary_uuid, 'Executable and dSYM LC_UUID mismatch')
    initializers = [section['segment'] + ',' + section['name'] for section in image.sections
                    if section['flags'] & 255 in (9, 0x16) and section['size']]
    return {'architecture': 'arm64', 'platform': 'iOS', 'minimumOS': version(minimum), 'sdk': version(sdk),
            'uuid': image.binary_uuid, 'dsymUUIDMatches': True if dsym_data is not None else None,
            'foundationModelsLoadCommand': 'LC_LOAD_WEAK_DYLIB', 'foundationModelsOrdinal': ordinal,
            'foundationModelsWeakSymbols': len(model_symbols), 'foundationModelsWeakChainedImports': len(weak_bindings),
            'initializerSections': initializers,
            'hasCodeSignatureCommand': any(command == 0x1D for command, _, _ in image.commands),
            'runtimeValidation': 'Static binary checks only; signed-device startup on iOS 18 still requires device QA.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=pathlib.Path)
    parser.add_argument('--dsym', type=pathlib.Path, help='Optional DWARF Mach-O to compare LC_UUID directly')
    parser.add_argument('--report', type=pathlib.Path, help='Optional JSON receipt (a .log file is preserved in CI artifacts)')
    args = parser.parse_args()
    try:
        report = audit_binary(args.binary.read_bytes(), args.dsym.read_bytes() if args.dsym else None)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(f"Binary audit passed: arm64 iOS {report['minimumOS']}, SDK {report['sdk']}, FoundationModels weak load and {report['foundationModelsWeakSymbols']} weak symbol/dyld imports, UUID {report['uuid']}")
    except (OSError, ValueError, UnicodeError, struct.error) as error:
        print('Binary audit failed: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
