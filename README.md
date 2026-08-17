# Sistema-OS

Aplicação single-file (HTML/CSS/JS) para gerenciamento de Ordens de Serviço de impressoras 3D.

Arquivos:
- `Sistema-OS.html` — aplicação principal (mobile-first).

## Configuração do Supabase

1. Abra o **SQL Editor** do projeto Supabase.
2. Execute todo o arquivo `supabase/schema_seguro.sql`. Ele pode ser reaplicado sobre a versão anterior.
3. Como o usuário master já existe em **Authentication**, execute o bloco de vinculação indicado no final do arquivo, substituindo `SEU_EMAIL_MASTER` pelo email real.
4. Não existe autocadastro na aplicação. Novos usuários são criados pelo master no painel **Gerenciamento de usuários**, com uma senha temporária obrigatoriamente alterada no primeiro login.
5. Em **Authentication > URL Configuration**, informe:
   - Site URL: `https://lacerdarnt.github.io/Sistema-OS/Sistema-OS.html`
   - Redirect URL: `https://lacerdarnt.github.io/Sistema-OS/Sistema-OS.html`
   - Para testes locais: `http://localhost:8000/Sistema-OS.html`

## Recuperação de senha

Na tela de login, informe o email e clique em **Esqueci minha senha**. O link enviado pelo Supabase retorna à aplicação em modo de recuperação, onde a nova senha deve ter pelo menos 8 caracteres. Ao concluir, a sessão temporária é encerrada e o usuário volta à tela de login.

## Criação e gerenciamento de usuários

O painel **Gerenciamento de usuários** aparece somente para o perfil master. Ele permite criar usuários como `viewer` ou `editor`, definir uma senha temporária e revogar acessos. No primeiro login, o usuário é obrigado a escolher uma senha nova antes de acessar qualquer OS. A senha temporária deve ser comunicada por um canal seguro.

As operações administrativas são executadas pela Edge Function `manage-users`; a chave `service_role` nunca é exposta no navegador e nenhum email de convite é necessário.

Depois de instalar e autenticar o Supabase CLI, publique a função:

```powershell
supabase link --project-ref vvkettfxdhfxysiracmh
supabase functions deploy manage-users
```

As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são disponibilizadas automaticamente no ambiente das Edge Functions hospedadas. Mantenha a verificação JWT habilitada.

Antes de usar o painel, reaplique `supabase/schema_seguro.sql` para instalar a função `is_authorized()` e as políticas de revogação imediata.

O `anon key` no HTML é próprio para uso no navegador. A proteção efetiva dos dados é feita pelas políticas RLS incluídas no SQL. Nunca coloque uma `service_role key` neste repositório.

## Publicação no GitHub Pages

1. Envie os arquivos para a branch `main`:

```bash
git branch -M main
git push -u origin main
```

2. Em **Settings > Pages**, selecione **Deploy from a branch**, branch `main` e pasta `/ (root)`.
3. Acesse `https://lacerdarnt.github.io/Sistema-OS/` e faça login.

## Verificação

- Usuário `viewer`: consulta e impressão, sem alteração/exclusão.
- Usuário `editor`: cria, edita, exclui e envia fotos/assinaturas.
- Se a nuvem estiver indisponível, o salvamento local permanece disponível e a interface informa a falha.

## Organização da OS e fotos

A OS mantém número, data de entrada e status fixos no topo. O restante é dividido nas abas Cliente, Equipamento, Check-in, Serviços realizados e Check-out. Ao salvar o status `Entregue`, a OS fica permanentemente bloqueada para edição também pelas políticas RLS.

Fotos de check-in e check-out são reduzidas no navegador para até 1280 px e JPEG com qualidade compactada antes do upload. Elas ficam no bucket privado `os-data`, enquanto o banco guarda somente os caminhos dos arquivos. Uma cópia comprimida pode permanecer no IndexedDB para funcionamento offline; esse armazenamento interno do navegador não aparece na galeria do celular. Fotos removidas são apagadas do bucket no próximo salvamento bem-sucedido.

Alternativas: Netlify, Cloudflare Pages.
