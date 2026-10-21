import json, math, collections, warnings
from pathlib import Path
import numpy as np
import networkx as nx
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyArrowPatch
from matplotlib.backends.backend_pdf import PdfPages
from adjustText import adjust_text

BASE=Path(__file__).resolve().parent
OUT=BASE/'figures'
import re
html=(BASE/'index.html').read_text()
match=re.search(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>',html,re.S)
if not match: raise ValueError('No embedded widget data in index.html')
p=json.loads(match.group(1))
n=p['x']['nodes'];e=p['x']['edges']
nodes={id:{k:v[i] for k,v in n.items()} for i,id in enumerate(n['id'])}
G=nx.DiGraph();G.add_nodes_from(nodes);G.add_edges_from(zip(e['from'],e['to']))
assert len(G)==317 and G.number_of_edges()==331
comps=sorted(nx.weakly_connected_components(G),key=lambda c:(-len(c),min(c)))
colors={'Mentor only':'#56B4E9','Both':'#E8B0D2','Trainee only':'#CBD5E1'}
plt.rcParams.update({'font.family':'DejaVu Sans','svg.fonttype':'none','pdf.fonttype':42,'font.size':9,'savefig.facecolor':'white'})
positions={}
for i,c in enumerate(comps):
 h=G.subgraph(c).to_undirected()
 if len(c)==2:
  ids=sorted(c);pos={ids[0]:np.array([-1.,0]),ids[1]:np.array([1.,0])}
 else:
  pos=nx.kamada_kawai_layout(h,pos=nx.spring_layout(h,seed=42),scale=1)
 # rotate major axis horizontal for small components
 if i>0 and len(c)>2:
  ids=sorted(c);a=np.array([pos[v] for v in ids]);_,_,vt=np.linalg.svd(a-a.mean(0),full_matrices=False);a=a@vt.T
  a=a/max(np.ptp(a[:,0]),np.ptp(a[:,1]),1e-6)*2
  pos=dict(zip(ids,a))
 positions[i]=pos


from matplotlib.backends.backend_pdf import PdfPages
OUT=BASE/'figures';OUT.mkdir(exist_ok=True)
selected={v for v in G if G.out_degree(v)>=3}
plt.rcParams.update({'font.size':8})
audit=[]
def draw(ax,ci,all_labels=False):
 c=comps[ci];pos=positions[ci];ids=sorted(c);a=np.array([pos[v] for v in ids]);ax.axis('off')
 ax.set_xlim(a[:,0].min()-.25,a[:,0].max()+.25)
 ax.set_ylim(a[:,1].min()-.25,a[:,1].max()+.25)
 if ci:ax.set_ylim(-1.45,1.45)
 scale=.19 if ci==0 else .17
 for u,v in G.subgraph(c).edges:
  rad=.12 if G.has_edge(v,u) else 0
  ax.add_patch(FancyArrowPatch(pos[u],pos[v],arrowstyle='-|>',mutation_scale=3.8 if ci==0 else 5,
   linewidth=.38 if ci==0 else .5,color='#83909D',alpha=.68,shrinkA=float(nodes[u]['size'])*scale+.2,
   shrinkB=float(nodes[v]['size'])*scale+.4,connectionstyle=f'arc3,rad={rad}',zorder=1))
 for v in ids:
  r=float(nodes[v]['size'])*scale
  ax.scatter(*pos[v],s=(2*r)**2,color=colors[nodes[v]['group']],edgecolors='#586778',linewidths=.4,zorder=3)
 txt=[];label_ids=ids if all_labels else sorted(c&selected)
 for v in label_ids:
  name=nodes[v]['label'];name=name.replace(', ', ',\n',1) if ci else name
  # Pairs have fixed labels above/below to avoid unnecessary leader lines.
  xy=pos[v].copy()
  if ci and len(c)==2:xy[1] += .48 if v==ids[0] else -.48
  txt.append(ax.text(*xy,name,fontsize=(9 if G.out_degree(v)>=5 else 8) if not ci else 7.8,ha='center',va='center',color='#14283C',
   zorder=5,bbox={'facecolor':'white','edgecolor':'none','alpha':.94,'pad':.6}))
 if txt and not (ci and len(c)==2):
  ax.figure.canvas.draw()
  adjust_text(txt,x=a[:,0],y=a[:,1],ax=ax,force_text=(.8,1),force_static=(.5,.7),force_pull=(.02,.02),
   expand=(1.12,1.2),iter_lim=160,min_arrow_len=2,ensure_inside_axes=True,
   arrowprops={'arrowstyle':'-','color':'#788C9E','lw':.35,'shrinkA':1,'shrinkB':4})
 # Resolve any remaining label overlap with small vertical shifts in display units.
 for attempt in range(60):
  ax.figure.canvas.draw();r=ax.figure.canvas.get_renderer()
  bb=[t.get_window_extent(r).expanded(1.04,1.08) for t in txt]
  pair=next(((i,j) for i in range(len(bb)) for j in range(i+1,len(bb)) if bb[i].overlaps(bb[j])),None)
  if pair is None:break
  i,j=pair
  a1,b1=bb[i],bb[j]
  shift=min(a1.y1,b1.y1)-max(a1.y0,b1.y0)+2
  sign=1 if a1.y0>=b1.y0 else -1
  for k,delta in [(i,sign*shift/2),(j,-sign*shift/2)]:
   xy=ax.transData.transform(txt[k].get_position());xy[1]+=delta
   box=bb[k];half=box.height/2;bounds=ax.get_window_extent()
   xy[1]=np.clip(xy[1],bounds.y0+half+1,bounds.y1-half-1)
   txt[k].set_position(ax.transData.inverted().transform(xy))
 ax.figure.canvas.draw();r=ax.figure.canvas.get_renderer();boxes=[t.get_window_extent(r).expanded(1.01,1.01) for t in txt]
 overlap=sum(b.overlaps(d) for i,b in enumerate(boxes) for d in boxes[i+1:])
 audit.append({'component':ci,'nodes':len(c),'edges':G.subgraph(c).number_of_edges(),'labels':len(txt),'overlaps':overlap})
 print('Panel',ci,'labels',len(txt),'overlaps',overlap,flush=True)
 return txt

def legend(fig,y=.045):
 handles=[Line2D([0],[0],marker='o',ls='',markerfacecolor=colors[k],markeredgecolor='#586778',markeredgewidth=.4,markersize=6,label=l)
  for k,l in [('Mentor only','Mentor only'),('Both','Mentor & trainee'),('Trainee only','Trainee only')]]
 fig.legend(handles=handles,loc='lower center',bbox_to_anchor=(.5,y),ncol=3,frameon=False,fontsize=8,handletextpad=.5,columnspacing=1.7)


# Orient the principal axis vertically; preserve every node and directed edge.
ids=sorted(comps[0]);a=np.array([positions[0][v] for v in ids]);a-=a.mean(axis=0)
_,_,vt=np.linalg.svd(a,full_matrices=False);a=a@vt.T
positions[0]=dict(zip(ids,np.column_stack((a[:,1],-a[:,0]))))
fig,ax=plt.subplots(figsize=(7,10),dpi=150)
fig.subplots_adjust(left=.035,right=.965,top=.96,bottom=.085)
ax.set_title('Largest connected component',loc='left',fontweight='bold',fontsize=10,pad=8)
draw(ax,0);legend(fig,.025)
fig.text(.5,.014,'190 people · Labels: 3+ direct trainees · Arrows: mentor to trainee',ha='center',fontsize=7,color='#425466')
fig.savefig(OUT/'mentorship_main.png',dpi=600)
fig.savefig(OUT/'mentorship_main.svg')
fig.savefig(OUT/'mentorship_main_portrait.pdf')
fig.savefig(OUT/'portrait_preview.png',dpi=150)
assert audit[0]['overlaps']==0
print(audit)
