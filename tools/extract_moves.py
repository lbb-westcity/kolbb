"""Rebuild the runtime's normal attack table from the approved GDD."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
rows={}
for line in (root/'docs/GDD.md').read_text().splitlines():
    c=[s.strip() for s in line.split('|')][1:-1]
    if len(c)!=7 or not re.fullmatch(r'(RW|JG|LB)-(5|2|j)[ABCD]',c[0]): continue
    s,a,r=map(int,c[2].split('/'));h,b=c[4].split('/')
    rows[c[0]]={'id':c[0],'name':c[1],'s':s,'a':a,'r':r,'damage':int(c[3]),'h':int(h) if h.isdigit() else 24,'b':int(b),'box':[int(v) for v in re.findall(r'-?\d+',c[5])],'level':'low' if '低段' in c[6] else 'overhead' if '中段' in c[6] else 'mid','launch':h=='浮空','hard':h=='硬倒地','cancel':''.join(k for k in 'LSQ' if k in c[6]),'cost':0,'kind':'normal'}
assert len(rows)==36
(root/'assets/moves.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print('36 normal moves extracted from GDD')
