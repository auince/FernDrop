import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

function harness() {
 const elements=new Map();
 const get=id=>{
  if(!elements.has(id)) elements.set(id,{value:'',writes:0,html:'',style:{},dataset:{},
   classList:{add(){},remove(){},toggle(){}},setAttribute(){},addEventListener(){},
   set innerHTML(value){this.html=value;this.writes++},get innerHTML(){return this.html}});
  return elements.get(id);
 };
 const context=vm.createContext({document:{getElementById:get,querySelectorAll:()=>[],addEventListener(){},body:get('body')},
  window:{scrollTo(){}},localStorage:{getItem:()=>null},Image:class{},setTimeout:()=>1,clearTimeout(){}});
 vm.runInContext(readFileSync(new URL('../ui/app.js',import.meta.url),'utf8'),context);
 return {context,get,update:data=>context.window.FernDrop.update(data)};
}
const records=Array.from({length:20_000},(_,index)=>({id:String(index),kind:'text',text:'x'.repeat(1000)+'END',name:String(index),createdAt:0,files:[],direction:'in'}));
test('legacy Windows snapshots render only 10 rows; repeat updates do not rebuild history',()=>{
 const h=harness();h.update({items:records});
 assert.equal((h.get('items').innerHTML.match(/<article /g)||[]).length,10);
 assert.ok(!h.get('items').innerHTML.includes('END'));
 const writes=h.get('items').writes;
 for(let i=0;i<100;i++) h.update({connected:i%2===0});
 assert.equal(h.get('items').writes,writes);
 vm.runInContext('refreshHistory(0)',h.context);
 assert.ok(h.get('items').innerHTML.includes('data-id="9"'));
 h.get('search').value='END';vm.runInContext('refreshHistory(0)',h.context);
 assert.equal((h.get('items').innerHTML.match(/<article /g)||[]).length,10);
});
test('native full-text matches are not filtered again using truncated display text',()=>{
 const h=harness();h.get('search').value='END';
 h.update({boundedHistory:true,historyTotal:10,historyMatches:1,historyOffset:0,items:[{...records[0],text:'summary'}]});
 assert.ok(h.get('items').innerHTML.includes('data-id="0"'));
 assert.equal(h.get('count').textContent,10);
});
