import http from 'node:http';
import {mkdirSync,existsSync,readFileSync,writeFileSync,renameSync,rmSync,readdirSync,statSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {timingSafeEqual,createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
export function createRelay({directory,token,quota=200_000_000,ttl=72*3600_000,clock=Date.now}={}) {
 if (!token || token.length<24) throw Error('FERNDROP_TOKEN must contain at least 24 characters');
 mkdirSync(directory,{recursive:true,mode:0o700});
 const indexPath=join(directory,'index.json');
 const saved=existsSync(indexPath)?JSON.parse(readFileSync(indexPath,'utf8')):{items:[],seq:0};
 let items=Array.isArray(saved)?saved:saved.items;
 let seq=Math.max(saved.seq||0,items.reduce((n,x)=>Math.max(n,x.seq),0)),reserved=0;
 const save=()=>{writeFileSync(indexPath+'.tmp',JSON.stringify({seq,items}),{mode:0o600});renameSync(indexPath+'.tmp',indexPath)};
 const cleanup=()=>{const expired=items.filter(x=>x.expiresAt<=clock());items=items.filter(x=>x.expiresAt>clock());for(const x of expired)rmSync(join(directory,x.id),{force:true});if(expired.length)save();};
 // Recover interrupted uploads and payloads that never committed their metadata.
 for(const name of readdirSync(directory))if(/^[a-f0-9-]{36}$/.test(name)&&!items.some(x=>x.id===name))rmSync(join(directory,name),{force:true});
 const digest=s=>createHash('sha256').update(s).digest();
 const authorized=req=>timingSafeEqual(digest(req.headers.authorization||''),digest('Bearer '+token));
 const json=(res,status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data))};
 const server=http.createServer(async(req,res)=>{
  try {
   const url=new URL(req.url,'http://relay');
   if(url.pathname==='/health')return json(res,200,{ok:true,protocol:1});
   if(!authorized(req))return json(res,401,{error:'unauthorized'});
   cleanup();const used=()=>items.reduce((n,x)=>n+x.bytes,0);
   if(req.method==='GET'&&url.pathname==='/v1/status')return json(res,200,{used:used(),quota,ttlSeconds:ttl/1000,items:items.length});
   if(req.method==='GET'&&url.pathname==='/v1/events') {
    const after=Number(url.searchParams.get('after')||0);return json(res,200,{cursor:seq,events:items.filter(x=>x.seq>after).map(({hash,...x})=>x)});
   }
   const m=url.pathname.match(/^\/v1\/items\/([a-f0-9-]{36})$/);if(!m)return json(res,404,{error:'not_found'});
   const id=m[1],existing=items.find(x=>x.id===id);
   if(req.method==='GET') {if(!existing)return json(res,410,{error:'expired_or_missing'});res.writeHead(200,{'Content-Type':'application/octet-stream','Cache-Control':'no-store','Content-Length':existing.bytes});res.end(readFileSync(join(directory,id)));return;}
   if(req.method!=='PUT')return json(res,405,{error:'method_not_allowed'});
   const length=Number(req.headers['content-length']);
   if(!Number.isSafeInteger(length)||length<29||length>28_000_000)return json(res,413,{error:'invalid_envelope_size'});
   const sender=String(req.headers['x-device-id']||'');if(!/^[a-f0-9-]{36}$/.test(sender))return json(res,400,{error:'invalid_device'});
   if(!existing&&used()+reserved+length>quota)return json(res,507,{error:'quota_exceeded'});
   reserved+=length;let body;
   try {const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>length)throw Error('body_too_large');chunks.push(chunk)}body=Buffer.concat(chunks);if(body.length!==length)throw Error('incomplete_body');}finally{reserved-=length;}
   const hash=createHash('sha256').update(body).digest('hex');
   // Re-check after awaiting the body: concurrent PUTs may have committed.
   const current=items.find(x=>x.id===id);
   if(current)return json(res,current.hash===hash?200:409,current.hash===hash?current:{error:'id_conflict'});
   if(used()+reserved+length>quota)return json(res,507,{error:'quota_exceeded'});
   const now=clock(),entry={id,sender,bytes:length,hash,seq:++seq,createdAt:now,expiresAt:now+ttl};
   writeFileSync(join(directory,id),body,{mode:0o600,flag:'wx'});items.push(entry);save();json(res,201,entry);
  }catch(e){if(!res.headersSent)json(res,400,{error:'invalid_request'});else res.destroy();}
 });
 server.requestTimeout=120_000;server.headersTimeout=15_000;
 const timer=setInterval(cleanup,60_000);timer.unref();server.on('close',()=>clearInterval(timer));
 return server;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const server=createRelay({directory:process.env.FERNDROP_DATA||'.data/relay',token:process.env.FERNDROP_TOKEN});
 server.listen(Number(process.env.PORT||8787),process.env.HOST||'127.0.0.1',()=>console.log('FernDrop relay ready on '+(process.env.PORT||8787)));
}
