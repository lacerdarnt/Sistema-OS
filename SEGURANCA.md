# 🔐 GUIA DE SEGURANÇA - Sistema-OS com Supabase

## Estado atual

- A aplicação oferece somente login; não existe autocadastro.
- O cabeçalho e as ações da aplicação permanecem ocultos até a sessão e o perfil serem validados.
- O usuário master deve existir em Authentication e também estar vinculado a `profiles` como `editor` e `is_master = true`.
- Como uma versão anterior do schema já foi executada, reaplique `supabase/schema_seguro.sql` antes de testar. O arquivo funciona como migração idempotente.

No final do schema há dois comandos comentados com `SEU_EMAIL_MASTER`. Substitua esse texto pelo email real do master, remova `--` dessas linhas e execute o bloco uma única vez no SQL Editor.

## ✅ SOLUÇÃO: 3 ETAPAS

---

# ETAPA 1: Resolver "Invalid Login Credentials"

## Passo 1.1: Verificar Configuração de Email

1. Vá para **Supabase Dashboard → Authentication → Providers**
2. Clique em **Email**
3. Procure a opção: **"Confirm email before signing in"**

### Se estiver HABILITADA (padrão):
Você **DEVE** confirmar o email antes de fazer login. Existem 3 soluções:

#### Opção A: Desabilitar Confirmação (Mais rápido, menos seguro)
```
1. Dashboard → Authentication → Providers → Email
2. DESABILITE: "Confirm email before signing in"
3. Clique SAVE
4. Tente fazer login novamente (mesma conta de cadastro)
```

#### Opção B: Confirmar Email Manualmente (Mais seguro)
```
1. Dashboard → Authentication → Users
2. Procure o email que cadastrou
3. Se tiver badge "Unconfirmed", clique no email
4. Procure botão "Confirm email" (ou ícone de verificação)
5. Clique para confirmar
6. Agora pode fazer login
```

#### Opção C: Habilitar Auto-Confirm no Cadastro (Recomendado)
```sql
-- Execute no SQL Editor do Supabase:
-- (Apenas se estiver usando função de signup customizada)
-- Normalmente já vem habilitado em novos projetos
```

---

# ETAPA 2: Configurar Segurança com Whitelist

## Passo 2.1: Executar Schema Seguro

1. **Abra SQL Editor** do Supabase
2. **Copie todo o conteúdo** de: `supabase/schema_seguro.sql`
3. **Cole no SQL Editor** e clique **RUN**
4. Aguarde terminar (sem erros)

⚠️ Se houver erro sobre "roles", execute isto antes:
```sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
```

## Passo 2.2: Criar Usuário Master

### A. Via Interface Supabase:
1. Dashboard → **Authentication → Users**
2. Clique **Add User**
3. Preencha:
   - Email: `admin@seudominio.com` (ou seu email)
   - Password: Senha forte (ex: `SenhaForte123!Mudar`)
   - ✅ Marque: **"Auto confirm"**
4. Clique **Create User**
5. **Copie o UID** gerado (aparece em "User ID")

### B. Via SQL (Usar UID copiado acima):
```sql
UPDATE public.profiles 
SET is_master = true, role = 'editor' 
WHERE email = 'admin@seudominio.com';
```

Pronto! Agora você é o **MASTER**.

## Passo 2.3: Adicionar Novos Usuários (Apenas Master)

Execute no SQL Editor:
```sql
INSERT INTO public.allowed_emails (email, role, approved_at)
VALUES 
  ('usuario1@exemplo.com', 'editor', now()),
  ('usuario2@exemplo.com', 'viewer', now());
```

- **editor** = pode criar/editar/deletar OSs
- **viewer** = apenas consulta

---

# ETAPA 3: Atualizar Sistema-OS.html

## Passo 3.1: Desabilitar Botão de Cadastro

**Encontre esta linha** no arquivo `Sistema-OS.html`:
```html
<button type="button" class="btn outline" id="authSignUpBtn">Cadastrar</button>
```

**Substitua por**:
```html
<!-- Cadastro desabilitado - Contato com admin -->
<button type="button" class="btn outline" id="authSignUpBtn" disabled title="Apenas o administrador pode criar usuários">Solicitar Acesso</button>
```

## Passo 3.2: Adicionar Aviso de Segurança

**Encontre**:
```html
<div class="c12"><p>Faça login com seu e-mail e senha para usar o sistema...</p></div>
```

**Substitua por**:
```html
<div class="c12">
  <p><strong>🔐 Sistema Seguro</strong></p>
  <p>Faça login com seu e-mail e senha. Apenas usuários autorizados podem acessar.</p>
  <p style="color:#666;font-size:11px;margin-top:10px;">
    Para solicitar acesso: <strong>contato@seudominio.com</strong>
  </p>
</div>
```

## Passo 3.3: Adicionar Mensagem de Erro se Email Não Autorizado

**Encontre a função `signIn`** no `<script>`:

```javascript
async function signIn(){
  if(!supabaseClient){ setAuthMessage('Supabase não disponível', true); return; }
  // ... resto do código ...
}
```

**Adicione esta validação ANTES do `signInWithPassword`**:

```javascript
// Verificar se email está na whitelist
const { data: allowedData } = await supabaseClient.from('allowed_emails')
  .select('id')
  .eq('email', email)
  .eq('approved_at is not null')
  .limit(1);

if (!allowedData || allowedData.length === 0) {
  setAuthMessage('Email não autorizado. Entre em contato com o administrador.', true);
  return;
}
```

---

# ETAPA 4: Teste Completo

## Teste 1: Login com Master
1. Faça login com: `admin@seudominio.com` / `SenhaForte123!`
2. Deve entrar normalmente como **EDITOR**

## Teste 2: Login com Usuário Não Autorizado
1. Tente fazer login com email não adicionado à whitelist
2. Deve retornar: **"Email não autorizado..."**

## Teste 3: Adicionar Novo Usuário
1. No Supabase, execute:
```sql
INSERT INTO public.allowed_emails (email, role, approved_at)
VALUES ('tecnico1@empresa.com', 'editor', now());
```

2. Esse novo usuário agora consegue:
   - ✅ Fazer login
   - ✅ Criar/editar OSs
   - ❌ NÃO consegue gerenciar outros usuários

## Teste 4: Visibilidade de Dados
1. Log in com **Master** → Vê todas as OSs
2. Log in com **Editor** → Vê todas as OSs, mas só edita as suas
3. Log in com **Viewer** → Vê todas, mas não consegue criar/editar

---

# 🔒 CHECKLIST DE SEGURANÇA

- [ ] Email confirmado para fazer login
- [ ] Schema seguro (`schema_seguro.sql`) executado
- [ ] Usuário Master criado e confirmado
- [ ] Whitelist de emails configurada
- [ ] Botão "Cadastrar" desabilitado no HTML
- [ ] Aviso de segurança exibido na tela de login
- [ ] Teste: Master consegue fazer login
- [ ] Teste: Email não autorizado é rejeitado
- [ ] Teste: Novo usuário consegue fazer login após adição à whitelist
- [ ] NUNCA coloque `service_role` key no código público

---

# 🚀 DEPLOYMENT NO GITHUB PAGES

```bash
# 1. Commit das mudanças
git add -A
git commit -m "🔐 Implementar segurança com whitelist e usuário master"
git push origin main

# 2. Aguarde GitHub Pages atualizar (1-2 min)

# 3. Teste em: https://lacerdarnt.github.io/Sistema-OS/
```

---

# ❓ TROUBLESHOOTING

### "Supabase não disponível"
- Verifique se `SUPABASE_URL` e `SUPABASE_ANON_KEY` estão corretos
- Verifique conexão de internet
- Abra DevTools (F12) → Console e verifique erros

### "Email não confirmado"
- Vá para Auth → Providers → Email
- Desabilite "Confirm email before signing in" OU
- Confirme o email manualmente em Auth → Users

### "Email não autorizado"
- Execute no SQL: `SELECT * FROM public.allowed_emails WHERE email = 'seu@email.com'`
- Verifique se `approved_at` **não é NULL**
- Se for NULL, atualize: `UPDATE public.allowed_emails SET approved_at = now() WHERE email = 'seu@email.com'`

### "RLS policy violation"
- Significa que o usuário não tem permissão
- Verifique o role: `SELECT * FROM public.profiles WHERE id = auth.uid()`
- Verifique as políticas: SQL Editor → Table → "Policies"

---

# 📝 NOTAS IMPORTANTES

1. **Nunca compartilhe**:
   - `service_role key` (apenas em backend seguro)
   - Senhas do Master
   - Database passwords

2. **Rotina semanal**:
   - Revisar `audit_log` para atividades suspeitas
   - Verificar usuários inativos

3. **Para múltiplos técnicos**:
   - 1 Master (gerencia usuarios)
   - N Editors (criam/editam OSs)
   - M Viewers (apenas consultam)

---

**Dúvidas?** Verifique o console (F12) para erros específicos.
