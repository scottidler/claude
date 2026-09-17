import json,os,re,collections
root='/home/saidler/.claude/skills'
user_skills={d for d in os.listdir(root) if os.path.isfile(os.path.join(root,d,'SKILL.md'))}
st=json.load(open('/home/saidler/.claude/settings.json'))
off=set(st.get('skillOverrides',{}).keys())
ALL=set(json.load(open(os.environ['TMPDIR']+'/skillnames.json')))
STRICT={n for n in ALL if (':' in n) or (n in user_skills)}
LOOSE=ALL
rows=json.load(open(os.environ['TMPDIR']+'/prompts.json'))
seen=set(); P=[]
for ts,_,t in rows:
    k=(ts,t)
    if k in seen: continue
    seen.add(k); P.append((ts,t))
TOK=re.compile(r'/([A-Za-z0-9][A-Za-z0-9_-]*)')
URLRX=re.compile(r'https?://\S+')
DATE=re.compile(r'\b\d{1,4}/\d{1,2}(/\d{1,4})?\b')

def spans_of(t):
    code=[m.span() for m in re.finditer(r'```.*?```',t,re.S)]+[m.span() for m in re.finditer(r'`[^`\n]*`',t)]
    url=[m.span() for m in URLRX.finditer(t)]
    return code,url

def classify(t,s,e,code,url):
    prev=t[s-1] if s>0 else ''
    nxt=t[e] if e<len(t) else ''
    if any(s>=a and e<=b for a,b in url): return 'url'
    if any(s>=a and e<=b for a,b in code): return 'code-span'
    if prev and (prev.isalnum() or prev in '._-~/'): return 'path-glued'
    if nxt=='/' : return 'path-continues'
    if nxt and (nxt in '.' and e+1<len(t) and t[e+1].isalnum()): return 'filename-ext'
    return None

for label,NAMES in (('STRICT (user skills + plugin:name)',STRICT),('LOOSE (+ bare plugin skill names)',LOOSE)):
    tot=0; fp=collections.Counter(); clean=collections.Counter(); prompts=set()
    ex=collections.defaultdict(list)
    for i,(ts,t) in enumerate(P):
        code,url=spans_of(t)
        for m in TOK.finditer(t):
            n=m.group(1)
            if n not in NAMES: continue
            tot+=1
            c=classify(t,m.start(),m.end(),code,url)
            if c:
                fp[c]+=1
                if len(ex[c])<6: ex[c].append((ts[:10],t[max(0,m.start()-55):m.end()+35].replace('\n',' ')))
            else:
                clean[n]+=1; prompts.add(i)
    print('==',label,'| names:',len(NAMES))
    print('  inline /token occurrences:',tot)
    print('  classified as path/url/code FALSE POSITIVES:',sum(fp.values()),dict(fp))
    print('  surviving (would fire):',sum(clean.values()),'across',len(prompts),'prompts')
    print('  survivors by name:',clean.most_common(20))
    if label.startswith('STRICT'):
        json.dump({k:v for k,v in ex.items()},open(os.environ['TMPDIR']+'/ex.json','w'),indent=1)
    print()
