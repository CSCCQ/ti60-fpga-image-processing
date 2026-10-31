"""Read-only dependency, initialization, and accepted-artifact checks."""
from pathlib import Path
import hashlib,json,re,struct,xml.etree.ElementTree as ET,zlib
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def required(p):
    p=p.resolve();assert p.is_relative_to(ROOT),('external dependency',p)
    assert p.is_file(),('missing dependency',p)
    return p
def main():
    xml=ET.parse(ROOT/'Ti60_Demo.xml').getroot();ns={'e':'http://www.efinixinc.com/enf_proj'}
    sources=set();inc=[ROOT]
    def source(p):
        p=required(p)
        if p in sources:return
        sources.add(p)
        if p.suffix=='.f':
            for line in p.read_text(encoding='utf-8-sig').splitlines():
                line=line.strip()
                if line and not line.startswith(('#','//')):source(p.parent/line)
    for e in xml.findall('.//e:design_file',ns):source(ROOT/e.attrib['name'])
    for tag in ['peri_file','sdc_file']:
        for e in xml.findall('.//e:'+tag,ns):required(ROOT/e.attrib['name'])
    for e in xml.findall('.//e:ip',ns):
        setting=required(ROOT/e.attrib['path']);read(setting)
        for s in e.findall('e:ip_src_file',ns):source(setting.parent/s.attrib['name'])
    for e in xml.findall('.//e:synthesis/e:param',ns):
        if e.attrib['name']=='include':
            p=(ROOT/e.attrib['value']).resolve();assert p.is_dir(),p;inc.append(p)
    pending=list(sources);headers=set()
    while pending:
        p=pending.pop()
        if p.suffix.lower() not in ['.v','.sv','.vh','.svh']:continue
        text=p.read_text(encoding='utf-8-sig',errors='replace')
        # Ignore comments before looking for literal include directives.
        text=re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)
        for name in re.findall(r'`include\s+"([^"]+)"',text):
            candidates=[d/name for d in [p.parent]+inc]
            found=next((c for c in candidates if c.is_file()),None)
            if found is None and re.fullmatch(r'tinyml_core[123]_define\.v',name):
                definitions=(ROOT/'src/tinyml/tinyml_defines.v').read_text()
                enabled=re.findall(r'^\s*`define\s+NUM_TINYML_CHANNEL_(\d)',definitions,re.M)
                assert enabled==['1'],('unexpected TinyML channel configuration',enabled)
                continue  # These includes are inside inactive channel 2/3/4 branches.
            assert found is not None,('missing include',p,name)
            found=required(found)
            if found not in headers:headers.add(found);pending.append(found)
        for name in re.findall(r'\$readmem[bh]\s*\(\s*"([^"]+)"',text):
            assert any((d/name).is_file() for d in [p.parent]+inc),('missing RAM initialization',p,name)
    accepted=read(ROOT/'release/release.json');manifest=read(ROOT/'release/boot/manifest.json')
    for path,key in [('release/fpga/Ti60_Demo.bit','bit_sha256'),('release/firmware/evsoc_tinyml_digits.elf','elf_sha256'),('ml/digits/artifacts/digits_int8.tflite','model_sha256')]:
        assert sha(ROOT/path)==accepted[key],('accepted artifact changed',path)
    firmware=bytes.fromhex((ROOT/'release/boot/digits_flash.hex').read_text())
    assert firmware==(ROOT/'release/boot/digits_flash.bin').read_bytes()
    assert sha(ROOT/'release/boot/digits_flash.bin')==manifest['image_sha256']
    magic,version,header,n,base,entry,crc,header_crc=struct.unpack_from('<8I',firmware)
    assert (magic,version,header,base,entry)==(0x44595247,1,64,0x1000,0x1000)
    assert n==len(firmware)-64==manifest['application_bytes']
    assert zlib.crc32(firmware[:28])==header_crc and zlib.crc32(firmware[64:])==crc==manifest['crc32']
    assert firmware[64:]==(ROOT/'release/firmware/evsoc_tinyml_digits.bin').read_bytes()
    assert len(bytes.fromhex((ROOT/'release/fpga/Ti60_Demo.hex').read_text()))<4194304
    for b in manifest['banks']:assert sha(ROOT/'ip/SapphireSoc32'/b['file'])==b['sha256']
    original=read(ROOT/'release/fpga/source_hashes.json')
    # Archived vendor simulation/example files are not compilation inputs.
    checked=0
    for name,h in original.items():
        p=ROOT/name
        if p.is_file():assert sha(p)==h.lower(),('original RTL fingerprint changed',name);checked+=1
        else:assert any(s=='Testbench' or s.endswith('_devkit') for s in Path(name).parts),('unexplained missing original source',name)
    for name,h in read(ROOT/'docs/verification/original/firmware_source_hashes.json').items():
        p=ROOT/name
        if not p.is_file() and '/tensorflow/lite/micro/examples/' in name.replace('\\','/'):
            continue  # Unused SDK examples are outside the application's makefile source globs.
        assert sha(required(p))==h.lower(),('firmware source changed',name)
    print(json.dumps({'passed':True,'design_and_IP_files':len(sources),'headers':len(headers),'original_source_fingerprints_checked':checked,'firmware_header_and_crc':True,'boot_ROM_banks':4,'accepted_bit_elf_model_match':True},indent=2))
if __name__=='__main__':main()
