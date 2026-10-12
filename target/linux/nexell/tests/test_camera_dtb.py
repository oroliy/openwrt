#!/usr/bin/env python3
"""Check the compiled camera graph, exclusive resources, IRQ and clock ABI."""
import struct,sys
from pathlib import Path

def parse(data):
    header=struct.unpack_from('>10I',data)
    assert header[0]==0xd00dfeed and header[1]<=len(data)
    start,strings=header[2],header[3]
    nodes={};stack=[];pos=start
    while True:
        token=struct.unpack_from('>I',data,pos)[0];pos+=4
        if token==1:
            end=data.index(b'\0',pos);stack.append(data[pos:end].decode());pos=(end+4)&~3
            nodes['/'.join(stack) or '/']={}
        elif token==2: stack.pop()
        elif token==3:
            length,nameoff=struct.unpack_from('>II',data,pos);pos+=8
            end=data.index(b'\0',strings+nameoff);name=data[strings+nameoff:end].decode()
            nodes['/'.join(stack) or '/'][name]=data[pos:pos+length];pos=(pos+length+3)&~3
        elif token==4: pass
        elif token==9: break
        else: raise AssertionError(f'unknown FDT token {token}')
    return nodes

def cells(data): return list(struct.unpack('>'+str(len(data)//4)+'I',data))
for arg in sys.argv[1:]:
    nodes=parse(Path(arg).read_bytes())
    cap=nodes['/soc@0/camera@c00d0000'];sensor=nodes['/i2c-cam/camera@3c']
    sink=nodes['/soc@0/camera@c00d0000/port/endpoint'];source=nodes['/i2c-cam/camera@3c/port/endpoint']
    assert cap['compatible']==b'nexell,s5p6818-capture\0' and cap['status']==b'okay\0'
    assert nodes['/soc@0/display@c0101000']['status']==b'disabled\0'
    assert sensor['status']==b'okay\0' and cells(sensor['reg'])==[0x3c]
    assert cells(sink['remote-endpoint'])==cells(source['phandle'])
    assert cells(source['remote-endpoint'])==cells(sink['phandle'])
    assert cells(sink['data-lanes'])==cells(source['data-lanes'])==[1,2]
    assert cells(cap['reg'])==[0xc00d0000,0x1000,0xc0063000,0x1000,0xc0011010,4]
    assert cells(cap['interrupts'])==[0,37,4]
    resets=cells(cap['resets'])
    assert resets[1::2]==[29,31,32,68,30,33]
    assert len(set(resets[::2]))==1
    assert cap['reset-names'].split(b'\0')[:-1]==[b'mipi',b'csi',b'phy',b'vip',b'dsi',b'phy-master']
    clock=nodes['/soc@0/clock-controller@c0010000']
    clkph=cells(clock['phandle'])[0]
    assert cells(cap['clocks'])==[clkph,15,clkph,20,clkph,3]
    assert clock['reg-names'].split(b'\0')[-2]==b'vip0'
    assert cells(clock['reg'])[-2:]==[0xc00c1000,0x1000]
    assert cells(nodes['/soc@0/thermal-sensor@c0096000']['clocks'])[-1]==19
    print(f'PASS: {arg}: reciprocal two-lane graph, VIP0 resources/IRQ, display exclusion, MIPI/VIP clock IDs and preserved thermal clock ABI')
assert len(sys.argv)>1, 'provide compiled DTB paths'
