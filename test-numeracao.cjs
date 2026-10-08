const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('Sistema-OS.html','utf8');
for(const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
const extract=(start,end)=>html.slice(html.indexOf(start),html.indexOf(end,html.indexOf(start)));
let generated=0,resets=0,stored=null,applied=null;
const fields={osNumero:{value:'OS-000010'},garantia:{},status:{dataset:{}},saveStatus:{}};
const c={DRAFT:'draft',currentId:null,currentCloudId:null,timer:null,savingOS:false,clearTimeout,console,confirm:()=>true,userCan:()=>true,$:id=>fields[id],localStorage:{getItem:()=>stored,removeItem(){stored=null},setItem(k,v){stored=v}},document:{getElementById:()=>({reset(){resets++;fields.osNumero.value=''}}),querySelectorAll:()=>[]},collect:()=>({fields:{osNumero:fields.osNumero.value}}),apply(d){applied=d;fields.osNumero.value=d.fields.osNumero;c.currentId=d.currentId||null},window:{scrollTo(){}},nextNumber:async()=>{generated++;return 'OS-000011'}};
for(const name of ['showPermissionDenied','lockCheckIn','syncStatusChecks','renderPhotos','clearSignature','setNow','setOSLocked','updateAuthUI','showOsTab'])c[name]=()=>{};
vm.createContext(c);
vm.runInContext(extract('let creatingNewOS=false;',"[$('novaBtn'),$('novaBtnTopo')]"),c);
vm.runInContext(extract('function restoreDraft(){','restoreDraft();'),c);
(async()=>{
await c.newOS();assert.equal(generated,0);assert.equal(resets,1);
fields.osNumero.value='';c.restoreDraft();assert.equal(applied.fields.osNumero,'OS-000010');await c.newOS();assert.equal(generated,0);assert.equal(fields.osNumero.value,'OS-000010');
c.currentId=42;await c.newOS();assert.equal(generated,1);await c.newOS();assert.equal(generated,1);
fields.osNumero.value='';await Promise.all([c.newOS(),c.newOS()]);assert.equal(generated,2);
c.savingOS=true;const before=resets;await c.newOS();assert.equal(resets,before);c.savingOS=false;
c.confirm=()=>false;await c.newOS();assert.equal(resets,before);
stored='{invalid';c.console={warn(){}};c.restoreDraft();
let inserts=0,updates=0,lookups=0;
c.console=console;c.currentUser={id:'user'};c.cloudErrorMessage=e=>e.message;
const savedResult=()=>({single:async()=>({data:{id:'cloud-id',os_numero:'OS-000020'}})});
c.supabaseClient={from(){return {
  insert(){inserts++;return {select:savedResult}},
  select(){lookups++;return {eq:()=>({single:async()=>({data:{id:'cloud-id',user_id:'user'}})})}},
  update(){updates++;return {eq:()=>({select:savedResult})}}
}}};
vm.runInContext(extract('async function saveToCloud(rec){','function req(r)'),c);
const rec={osNumero:'OS-000011',fields:{osNumero:'OS-000011'},photos:{entrada:[],saida:[]},cloudId:null};
await c.saveToCloud(rec);assert.equal(inserts,1);assert.equal(lookups,0);assert.equal(updates,0);assert.equal(rec.osNumero,'OS-000020');assert.equal(rec.fields.osNumero,'OS-000020');assert.equal(c.currentCloudId,'cloud-id');
await c.saveToCloud(rec);assert.equal(updates,1);assert.equal(lookups,1);assert.equal(inserts,1);
console.log('OK JS: syntax, draft restore after refresh, unsaved number reuse, saved order, concurrent clicks, save guard, cancel, safe insert, server number and UUID update.');
})().catch(e=>{console.error(e);process.exitCode=1});
