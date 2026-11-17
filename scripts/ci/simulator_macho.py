"""Read-only, bounded Mach-O platform evidence for a Simulator executable.

This inspects the actual file bytes; it never loads or executes the image.
Universal tables may be FAT32/FAT64 and either endian, but their slices must
be supported 64-bit Mach-O images with matching CPU identities.
"""
import base64
import hashlib
import struct


class MachOInspectionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MachOInspectionError(message)


def architecture(cpu, subtype):
    family = {
        (0x01000007, 3): "x86_64", (0x01000007, 8): "x86_64h",
        (0x0100000C, 0): "arm64", (0x0100000C, 2): "arm64e",
    }
    result = family.get((cpu, subtype & 0x00FFFFFF))
    require(result is not None, "Unsupported 64-bit Simulator CPU/subtype.")
    return result


def inspect_simulator_executable(data, native_architecture):
    """Require every slice to identify PLATFORM_IOSSIMULATOR (7).

    Return original header/load-command bytes so the receipt can be decoded
    independently. The selected native architecture must occur exactly once.
    """
    require(native_architecture in ("arm64", "x86_64"), "Unsupported native Simulator architecture.")
    require(isinstance(data, bytes) and 32 <= len(data) <= 128 * 1024 * 1024,
            "Invalid or unbounded executable size.")
    thin_magics = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}
    fat_magics = {
        b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
        b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True),
    }
    magic = data[:4]
    table_end = 0
    if magic in thin_magics:
        slices = [(0, len(data), None, None)]
        image_format = "thin64"
        container_header = data[:32]
    else:
        require(magic in fat_magics, "Unsupported executable/container magic; 64-bit Mach-O required.")
        endian, wide = fat_magics[magic]
        count = struct.unpack_from(endian + "I", data, 4)[0]
        stride = 32 if wide else 20
        table_end = 8 + count * stride
        require(1 <= count <= 16 and table_end <= len(data), "Invalid universal architecture table.")
        slices = []
        for index in range(count):
            position = 8 + index * stride
            cpu, subtype = struct.unpack_from(endian + "II", data, position)
            offset, size, align = struct.unpack_from(endian + ("QQI" if wide else "III"), data, position + 8)
            if wide:
                require(struct.unpack_from(endian + "I", data, position + 28)[0] == 0,
                        "Nonzero reserved universal-slice field.")
            require(0 <= align <= 31 and offset % (1 << align) == 0, "Invalid universal-slice alignment.")
            require(size >= 32 and table_end <= offset <= len(data) and size <= len(data) - offset,
                    "Universal slice escapes its actual file.")
            slices.append((offset, size, cpu, subtype))
        intervals = sorted((offset, offset + size) for offset, size, _, _ in slices)
        require(all(left[1] <= right[0] for left, right in zip(intervals, intervals[1:])),
                "Universal executable slices overlap.")
        image_format = "universal64" if wide else "universal32"
        container_header = data[:table_end]

    inspected, identities = [], set()
    for offset, size, declared_cpu, declared_subtype in slices:
        require(data[offset:offset + 4] in thin_magics, "A universal slice must contain a thin 64-bit Mach-O.")
        endian = thin_magics[data[offset:offset + 4]]
        header = data[offset:offset + 32]
        _, cpu, subtype, kind, count, command_bytes, flags, reserved = struct.unpack(endian + "8I", header)
        require(declared_cpu is None or (cpu, subtype) == (declared_cpu, declared_subtype),
                "Universal CPU identity differs from its actual thin slice.")
        name = architecture(cpu, subtype)
        require((cpu, subtype) not in identities, "Duplicate/ambiguous universal CPU identity.")
        identities.add((cpu, subtype))
        require(kind == 2, "The runtime tool must be an MH_EXECUTE image.")
        require(1 <= count <= 4096 and 8 * count <= command_bytes <= 1024 * 1024
                and command_bytes <= size - 32, "Invalid or unbounded load-command inventory.")
        commands = data[offset + 32:offset + 32 + command_bytes]
        position, builds = 0, []
        for _ in range(count):
            require(position + 8 <= len(commands), "Truncated load-command header.")
            command, command_size = struct.unpack_from(endian + "II", commands, position)
            require(command_size >= 8 and command_size % 8 == 0 and command_size <= len(commands) - position,
                    "Invalid load-command bounds/alignment.")
            require(command not in (0x24, 0x25, 0x2F, 0x30), "Legacy platform commands are not accepted for this runtime tool.")
            if command == 0x32:  # LC_BUILD_VERSION
                require(command_size >= 24, "Truncated LC_BUILD_VERSION.")
                platform, minimum, sdk, tools = struct.unpack_from(endian + "4I", commands, position + 8)
                require(tools <= 4096 and command_size == 24 + tools * 8,
                        "LC_BUILD_VERSION tool count/size mismatch.")
                require(platform == 7, "The runtime launchctl must be built for iOS Simulator, never macOS/device iOS.")
                builds.append(dict(platform=platform, minimumOS=minimum, sdk=sdk,
                                   tools=[dict(tool=tool, version=version) for tool, version in
                                          (struct.unpack_from(endian + "II", commands, position + 24 + index * 8)
                                           for index in range(tools))]))
            position += command_size
        require(position == len(commands), "Load-command count and byte size disagree.")
        require(len(builds) == 1, "Exactly one LC_BUILD_VERSION is required per runtime-tool slice.")
        inspected.append(dict(offset=offset, byteCount=size, architecture=name, cpuType=cpu, cpuSubtype=subtype,
                              fileType=kind, endianness="little" if endian == "<" else "big",
                              loadCommandCount=count, loadCommandBytes=command_bytes,
                              headerBase64=base64.b64encode(header).decode("ascii"),
                              loadCommandsBase64=base64.b64encode(commands).decode("ascii"),
                              loadCommandsSHA256=hashlib.sha256(commands).hexdigest(), buildVersion=builds[0]))
    require(sum(item["architecture"] == native_architecture for item in inspected) == 1,
            "The actual runtime tool must contain exactly one selected native architecture.")
    return dict(schemaVersion=1, inspection="read-only Mach-O LC_BUILD_VERSION bytes; no tool execution",
                format=image_format, byteCount=len(data), sha256=hashlib.sha256(data).hexdigest(),
                nativeArchitecture=native_architecture, platforms=[7],
                containerHeaderBase64=base64.b64encode(container_header).decode("ascii"), slices=inspected)
