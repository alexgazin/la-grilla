#!/usr/bin/env python3
"""Binary-format guard fixtures, never native/platform readiness acceptance."""
import base64
import hashlib
import struct
import unittest
from simulator_macho import MachOInspectionError, inspect_simulator_executable


CPUS = {"arm64": (0x0100000C, 0), "x86_64": (0x01000007, 3)}


def build_command(platform=7, tools=()):
    return struct.pack("<6I", 0x32, 24 + len(tools) * 8, platform, 0x1A0200, 0x1A0200, len(tools)) + b"".join(
        struct.pack("<II", *tool) for tool in tools)


def thin(architecture="arm64", platform=7, commands=None, kind=2, cpu=None):
    commands = [build_command(platform)] if commands is None else commands
    cpu, subtype = CPUS[architecture] if cpu is None else cpu
    payload = b"".join(commands)
    return struct.pack("<8I", 0xFEEDFACF, cpu, subtype, kind, len(commands), len(payload), 0, 0) + payload


def fat(images, wide=False, endian=">"):
    stride = 32 if wide else 20
    offset = 8 + stride * len(images)
    entries, payload = [], []
    for image in images:
        cpu, subtype = struct.unpack_from("<II", image, 4)
        entry = struct.pack(endian + ("IIQQII" if wide else "IIIII"), cpu, subtype, offset, len(image), 0, *([0] if wide else []))
        entries.append(entry)
        payload.append(image)
        offset += len(image)
    return struct.pack(endian + "II", 0xCAFEBABF if wide else 0xCAFEBABE, len(images)) + b"".join(entries + payload)


class SimulatorMachOTests(unittest.TestCase):
    def rejected(self, image, architecture="arm64"):
        with self.assertRaises(MachOInspectionError):
            inspect_simulator_executable(image, architecture)

    def test_actual_platform_and_native_identity_are_required(self):
        for architecture in CPUS:
            with self.subTest(architecture=architecture):
                image = thin(architecture)
                proof = inspect_simulator_executable(image, architecture)
                self.assertEqual(proof["platforms"], [7])
                self.assertEqual(proof["nativeArchitecture"], architecture)
                self.assertEqual(proof["sha256"], hashlib.sha256(image).hexdigest())
                self.assertEqual(proof["slices"][0]["cpuType"], CPUS[architecture][0])
        self.rejected(thin("x86_64"))
        self.rejected(thin(), "unsupported")

    def test_original_bytes_allow_independent_load_command_decode(self):
        image = thin(commands=[struct.pack("<II16s", 0x1B, 24, b"\1" * 16), build_command(tools=[(3, 0x1234)])])
        proof = inspect_simulator_executable(image, "arm64")
        item = proof["slices"][0]
        self.assertEqual(base64.b64decode(item["headerBase64"]), image[:32])
        raw = base64.b64decode(item["loadCommandsBase64"])
        self.assertEqual(raw, image[32:])
        self.assertEqual(struct.unpack_from("<I", raw, 32)[0], 7)
        self.assertEqual(item["loadCommandsSHA256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(item["buildVersion"]["tools"], [dict(tool=3, version=0x1234)])

    def test_universal32_and64_both_table_endians(self):
        for wide in (False, True):
            for endian in ("<", ">"):
                image = fat([thin(), thin("x86_64")], wide, endian)
                proof = inspect_simulator_executable(image, "arm64")
                self.assertEqual([item["architecture"] for item in proof["slices"]], ["arm64", "x86_64"])
                self.assertEqual(proof["format"], "universal64" if wide else "universal32")
                self.assertEqual(base64.b64decode(proof["containerHeaderBase64"]), image[:8 + (32 if wide else 20) * 2])

    def test_wrong_platform_in_any_slice_is_rejected(self):
        for platform in (0, 1, 2, 6, 8, 99):
            self.rejected(thin(platform=platform))
            self.rejected(fat([thin(), thin("x86_64", platform)]))

    def test_no_missing_or_duplicate_build_version(self):
        self.rejected(thin(commands=[struct.pack("<2I", 0x1B, 8)]))
        self.rejected(thin(commands=[build_command(), build_command()]))
        self.rejected(thin(commands=[]))

    def test_conflicting_legacy_version_is_rejected(self):
        for kind in (0x24, 0x25, 0x2F, 0x30):
            self.rejected(thin(commands=[struct.pack("<4I", kind, 16, 0x1A0200, 0x1A0200), build_command()]))

    def test_executable_kind_and_supported_cpu_are_required(self):
        self.rejected(thin(kind=6))
        self.rejected(thin(cpu=(0x01000012, 0)))
        self.rejected(thin(cpu=(0x0100000C, 42)))
        self.rejected(thin(cpu=(7, 3)))

    def test_universal_table_cannot_lie_about_cpu_or_subtype(self):
        image = bytearray(fat([thin()]))
        struct.pack_into(">I", image, 8, CPUS["x86_64"][0])
        self.rejected(bytes(image))
        image = bytearray(fat([thin()]))
        struct.pack_into(">I", image, 12, 2)
        self.rejected(bytes(image))

    def test_duplicate_universal_architectures_are_ambiguous(self):
        self.rejected(fat([thin(), thin()]))
        self.rejected(fat([thin(), thin(cpu=(0x0100000C, 0x80000000))]))

    def test_universal_alignment_and_reserved_field(self):
        image = bytearray(fat([thin()], wide=True))
        struct.pack_into(">I", image, 36, 1)
        self.rejected(bytes(image))
        image = bytearray(fat([thin()]))
        struct.pack_into(">I", image, 24, 31)
        self.rejected(bytes(image))

    def test_universal_slices_cannot_overlap_table_or_each_other(self):
        image = bytearray(fat([thin(), thin("x86_64")]))
        struct.pack_into(">I", image, 36, 48)
        self.rejected(bytes(image))
        image = bytearray(fat([thin()]))
        struct.pack_into(">I", image, 16, 8)
        self.rejected(bytes(image))

    def test_universal_slice_bounds_and_inventory(self):
        for position, value in ((4, 0), (4, 17), (16, 0xFFFFFFFE), (20, 0xFFFFFFFE)):
            image = bytearray(fat([thin()]))
            struct.pack_into(">I", image, position, value)
            self.rejected(bytes(image))
        self.rejected(fat([thin()], wide=True)[:-1])
        self.rejected(fat([thin()])[:24])

    def test_load_command_bounds_alignment_and_count(self):
        for position, value in ((16, 4097), (16, 0), (20, 0x100001), (20, 8), (36, 0), (36, 12), (36, 32)):
            image = bytearray(thin())
            struct.pack_into("<I", image, position, value)
            self.rejected(bytes(image))
        self.rejected(thin()[:-1])

    def test_build_version_tool_inventory_is_not_trusted(self):
        image = bytearray(thin())
        struct.pack_into("<I", image, 52, 1)
        self.rejected(bytes(image))
        self.rejected(thin(commands=[struct.pack("<4I", 0x32, 16, 7, 0)]))
        image = bytearray(thin(commands=[build_command(tools=[(3, 1)])]))
        struct.pack_into("<I", image, 52, 4097)
        self.rejected(bytes(image))

    def test_truncated_unknown_32_bit_or_nested_container(self):
        for data in (b"", b"\xcf\xfa\xed\xfe", b"z" * 56, bytes.fromhex("cefaedfe") + b"\0" * 52):
            self.rejected(data)
        image = bytearray(fat([thin()]))
        image[28:32] = bytes.fromhex("cafebabe")
        self.rejected(bytes(image))


if __name__ == "__main__":
    unittest.main()
