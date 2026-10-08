const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {PGlite}=require('@electric-sql/pglite');
(async()=>{
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create function public.has_permission(text) returns boolean language sql as 'select true';create table public.ordens(id uuid primary key default gen_random_uuid(),os_numero text not null unique,data jsonb not null default '{}');insert into public.ordens(os_numero) values ('OS-000007');`);
const sql=fs.readFileSync('supabase/corrigir_numeracao_definitiva.sql','utf8');await db.exec(sql);
const preview=async()=>(await db.query('select public.preview_os_number() as n')).rows[0].n;
assert.equal(await preview(),'OS-000008');assert.equal(await preview(),'OS-000008');
await db.exec('begin');await db.query("insert into public.ordens(os_numero) values ('IGNORED')");await db.exec('rollback');assert.equal(await preview(),'OS-000008');
let r=await db.query("insert into public.ordens(os_numero) values ('OS-000001') returning os_numero,data");assert.equal(r.rows[0].os_numero,'OS-000008');assert.equal(r.rows[0].data.osNumero,'OS-000008');
await db.exec("delete from public.ordens where os_numero='OS-000008'");assert.equal(await preview(),'OS-000009');await db.exec(sql);assert.equal(await preview(),'OS-000009');
r=await db.query("insert into public.ordens(os_numero) values ('same'),('same') returning os_numero");assert.deepEqual(r.rows.map(x=>x.os_numero),['OS-000009','OS-000010']);
await assert.rejects(db.query("update public.ordens set os_numero='changed' where os_numero='OS-000009'"));
r=await db.query("select a.attname from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=any(c.conkey) where c.conrelid='public.ordens'::regclass and c.contype='p'");assert.equal(r.rows[0].attname,'os_numero');
assert.equal((await db.query("select count(*)::int as n from public.ordens where os_numero='OS-000007'")).rows[0].n,1);
await db.close();console.log('OK SQL: migration, primary key, existing data, preview, rollback, insert, no reuse after deletion, idempotence, multiple inserts, immutable number.');
})().catch(e=>{console.error(e);process.exitCode=1});
