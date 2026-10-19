"""Check x64 PE binaries, GUI subsystem, icon resources, and DLL dependency closure."""
import pathlib,re,struct,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
folder=root/'dist/windows-x86_64/bin'
exe=folder/'ember.exe'
files=[exe,*folder.glob('*.dll'),*folder.glob('cores/*.dll')]
available={p.name.lower() for p in folder.glob('*.dll')}
system={'advapi32.dll','bcrypt.dll','crypt32.dll','gdi32.dll','imm32.dll','kernel32.dll','kernelbase.dll','msvcrt.dll','ntdll.dll','ole32.dll','oleaut32.dll','rpcrt4.dll','secur32.dll','setupapi.dll','shell32.dll','shlwapi.dll','user32.dll','userenv.dll','version.dll','winmm.dll','ws2_32.dll','ucrtbase.dll'}
for file in files:
    data=file.read_bytes();assert data[:2]==b'MZ',file
    pe=struct.unpack_from('<I',data,0x3c)[0]
    assert data[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',data,pe+4)[0]==0x8664,file
    text=subprocess.check_output(['objdump','-p',str(file)],text=True)
    for dll in re.findall(r'DLL Name: (\S+)',text):
        assert dll.lower() in available|system or dll.lower().startswith(('api-ms-win-','ext-ms-win-')),(file.name,'missing',dll)
    if file==exe:
        assert struct.unpack_from('<H',data,pe+24+68)[0]==2,'Expected Windows GUI subsystem'
        sections=subprocess.check_output(['objdump','-h',str(file)],text=True)
        assert '.rsrc' in sections,'Missing embedded icon/version resource'
        resource_rva=struct.unpack_from('<I',data,pe+24+112+16)[0]
        section_count=struct.unpack_from('<H',data,pe+6)[0]
        section_table=pe+24+struct.unpack_from('<H',data,pe+20)[0]
        for i in range(section_count):
            offset=section_table+40*i
            virtual_size,rva,raw_size,raw_offset=struct.unpack_from('<IIII',data,offset+8)
            if rva<=resource_rva<rva+max(virtual_size,raw_size):
                directory=raw_offset+resource_rva-rva
                named,ids=struct.unpack_from('<HH',data,directory+12)
                types={struct.unpack_from('<I',data,directory+16+8*j)[0] for j in range(named+ids)}
                assert {3,14,16}<=types,'Missing icon, icon group, or version metadata'
                break
        else:raise AssertionError('Resource directory not found')
    print('PASS',file.name)
assert (folder/'cores/snes9x_libretro.dll').exists()
assert not list(folder.rglob('*.so')),'Linux core in Windows package'
assert (folder/'assets/brand/ember.ico').exists()
print('Windows package structure and DLL dependencies verified. Runtime testing still requires Windows or Wine.')
