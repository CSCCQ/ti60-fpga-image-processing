"""Build a checked flash application image and a <=4 KiB ROM bootloader."""
from pathlib import Path
import hashlib, json, struct, subprocess, zlib, argparse, os
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/boot'
IDE = Path(os.environ.get('GRAY_RISCV_IDE', 'E:/Efinity/efinity-riscv-ide-2026.1')) / 'toolchain/bin'
SW = ROOT / 'embedded_sw/SapphireSoc32'
APP = SW / 'software/standalone/evsoc/build'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args): subprocess.run([str(x) for x in args], cwd=ROOT, check=True)
def main():
    p=argparse.ArgumentParser(); p.add_argument('--install-rom', action='store_true'); args=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    elf=APP/'evsoc_tinyml_digits.elf'; raw=OUT/'application.bin'
    run([IDE/'riscv-none-elf-objcopy.exe','-O','binary',elf,raw])
    data=raw.read_bytes(); e=elf.read_bytes(); entry=struct.unpack_from('<I',e,24)[0]
    assert e[:6]==b'\x7fELF\x01\x01' and entry==0x1000
    assert data==(APP/'evsoc_tinyml_digits.bin').read_bytes(), 'Stale application binary'
    assert 0<len(data)<=0x400000-64
    header=struct.pack('<7I',0x44595247,1,64,len(data),0x1000,entry,zlib.crc32(data))
    header+=struct.pack('<I',zlib.crc32(header))+b'\xff'*32
    image=OUT/'digits_flash.bin'; image.write_bytes(header+data)
    # Efinity's .hex is raw bytes, one hexadecimal byte per line (NOT Intel HEX).
    (OUT/'digits_flash.hex').write_text(''.join(f'{b:02X}\n' for b in header+data))
    gcc=IDE/'riscv-none-elf-gcc.exe'; boot=OUT/'gray_flash_boot.elf'
    run([gcc,'-march=rv32im_zicsr_zifencei','-mabi=ilp32','-Os','-g',
         '-ffreestanding','-fno-builtin','-msmall-data-limit=0','-fno-pic',
         '-ffunction-sections','-fdata-sections','-nostdlib',
         '-I'+str(SW/'software/standalone/driver'),'-I'+str(SW/'bsp/efinix/EfxSapphireSoc/include'),
         '-Wl,--gc-sections,--no-warn-rwx-segment,-Map,'+str(OUT/'gray_flash_boot.map'),
         '-T',HERE/'boot.ld',HERE/'start.S',HERE/'boot.c','-o',boot,'-lgcc'])
    rom=OUT/'gray_flash_boot.bin'; run([IDE/'riscv-none-elf-objcopy.exe','-O','binary',boot,rom])
    rb=rom.read_bytes(); assert len(rb)<=0xd00 and struct.unpack_from('<I',rb,4)[0]==0x42595247
    with (OUT/'gray_flash_boot.asm').open('w') as f:
        subprocess.run([str(IDE/'riscv-none-elf-objdump.exe'),'-d',str(boot)],stdout=f,check=True)
    padded=rb.ljust(4096,b'\0'); banks=[]
    for i in range(4):
        name=f'EfxSapphireSoc.v_toplevel_system_ramA_logic_ram_symbol{i}.bin'
        text=''.join(f'{v:08b}\n' for v in padded[i::4]); (OUT/name).write_text(text)
        if args.install_rom: (ROOT/'ip/SapphireSoc32'/name).write_text(text)
        banks.append({'file':name,'sha256':sha(OUT/name)})
    report={'flash_bytes':0x800000,'fpga_offset':0,'application_offset':0x400000,
            'header_bytes':64,'application_bytes':len(data),'entry':entry,'crc32':zlib.crc32(data),
            'elf_sha256':sha(elf),'application_sha256':sha(raw),'image_sha256':sha(image),
            'boot_bytes':len(rb),'boot_sha256':sha(rom),'rom_installed':args.install_rom,'banks':banks}
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
