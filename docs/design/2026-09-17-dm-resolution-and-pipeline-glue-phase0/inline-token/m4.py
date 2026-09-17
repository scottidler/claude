import json,os,re,collections,random
root='/home/saidler/.claude/skills'
user_skills={d for d in os.listdir(root) if os.path.isfile(os.path.join(root,d,'SKILL.md'))}
ALL=set(json.load(open(os.environ['TMPDIR']+'/skillnames.json')))
STRICT={n for n in ALL if (':' in n) or (n in user_skills)}
rows=json.load(open(os.environ['TMPDIR']+'/prompts.json'))
seen=set(); P=[]
for ts,_,t in rows:
    k=(ts,t)
    if k in seen: continue
    seen.add(k); P.append((ts,t))
TOK=re.compile(r'/([A-Za-z0-9][A-Za-z0-9_-]*)')
URLRX=re.compile(r'https?://\S+')
def spans_of(t):
    return ([m.span() for m in re.finditer(r'```.*?```',t,re.S)]+[m.span() for m in re.finditer(r'`[^`\n]*`',t)],
            [m.span() for m in URLRX.finditer(t)])
def classify(t,s,e,code,url):
    prev=t[s-1] if s>0 else ''; nxt=t[e] if e<len(t) else ''
    if any(s>=a and e<=b for a,b in url): return 'url'
    if any(s>=a and e<=b for a,b in code): return 'code-span'
    if prev and (prev.isalnum() or prev in '._-~/'): return 'path-glued'
    if nxt=='/': return 'path-continues'
    if nxt=='.' and e+1<len(t) and t[e+1].isalnum(): return 'filename-ext'
    return None
sur=[]
for ts,t in P:
    code,url=spans_of(t)
    for m in TOK.finditer(t):
        n=m.group(1)
        if n not in STRICT: continue
        if classify(t,m.start(),m.end(),code,url): continue
        sur.append((ts[:10],n,t[max(0,m.start()-80):m.end()+60].replace('\n',' ')))
print('survivors:',len(sur))
random.seed(7)
for ts,n,s in random.sample(sur,70):
    print(f'{ts} /{n} :: {s}')
