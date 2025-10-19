# Harden SSH — Guia rápido para meu eu do futuro

> Este arquivo explica o que faz o script `harden.sh`, como usá-lo com segurança e como reverter se algo der errado. Escrito em linguagem direta para quem não lembrar do contexto.

---

## Objetivo

Deixar uma VPS (Ubuntu/Debian) **segura por padrão**: aceitar apenas autenticação por chave SSH, configurar firewall (UFW), instalar `fail2ban`, habilitar atualizações automáticas e (opcional) criar um usuário sudo. O script é *plug and play* mas exige atenção — não se tranque fora.

## O que o script faz (resumo)

* Instala pacotes: `openssh-server`, `ufw`, `fail2ban`, `unattended-upgrades`, `ca-certificates`.
* Garante que a sua chave pública exista em `/root/.ssh/authorized_keys` e (opcional) em `/home/USER/.ssh/authorized_keys` quando você pede para criar usuário.
* Ajusta `/etc/ssh/sshd_config` para:

  * `PubkeyAuthentication yes`
  * `PasswordAuthentication no`
  * `ChallengeResponseAuthentication no`
  * `PermitRootLogin prohibit-password` (ou `no` se especificado)
  * `AuthorizedKeysFile .ssh/authorized_keys`
* Reinicia o serviço `sshd` depois de validar a configuração.
* Reseta e configura UFW: `deny incoming` por padrão, permite saída, permite + rate-limit na porta SSH escolhida.
* Cria configuração básica do `fail2ban` para proteger `sshd`.
* Habilita updates automáticos via `unattended-upgrades`.

---

## Pré-requisitos antes de rodar

1. **Tenha sua chave pública pronta** (arquivo `.pub`) — preferencialmente `~/.ssh/id_ed25519.pub`.
2. Conecte-se via SSH **com a sessão atual aberta** (não feche a sessão até confirmar que a chave funciona). Abra um segundo terminal para testar após rodar o script.
3. Execute como `root` (ou via `sudo`).
4. O script foi escrito para **Debian/Ubuntu**. Em outras distros pode falhar.

---

## Como usar (comandos)

1. Salve o script em um arquivo local chamado `harden.sh` e torne executável:

```bash
chmod +x harden.sh
```

2. Rodar no modo **básico** (mantendo root por chave, sem criar usuário):

```bash
sudo bash harden.sh --pubkey-file ~/.ssh/id_ed25519.pub
```

3. Rodar criando um novo usuário sudo (`deploy`) e instalando a chave nele (porta SSH default 22):

```bash
sudo bash harden.sh --user deploy --pubkey-file ~/.ssh/id_ed25519.pub
```

4. Rodar criando o user e trocando a porta do SSH para 2222:

```bash
sudo bash harden.sh --user deploy --pubkey-file ~/.ssh/id_ed25519.pub --ssh-port 2222
```

5. Depois de confirmar que o novo usuário funciona, desative login root por SSH com a flag `--disable-root`:

```bash
sudo bash harden.sh --user deploy --pubkey-file ~/.ssh/id_ed25519.pub --disable-root
```

> **Importante:** sempre teste a conexão SSH em outra aba/terminal antes de fechar a sessão original.

---

## O que verificar imediatamente após rodar

1. Em outro terminal, teste com a chave:

```bash
# se porta padrão
ssh -i ~/.ssh/id_ed25519 root@SEU_IP
# ou, se criou deploy e trocou porta
ssh -p 2222 -i ~/.ssh/id_ed25519 deploy@SEU_IP
```

2. Verifique status do sshd:

```bash
sudo systemctl status sshd -l
```

3. Verifique se UFW está ativo e regras:

```bash
sudo ufw status verbose
```

4. Verifique fail2ban:

```bash
sudo systemctl status fail2ban
sudo fail2ban-client status sshd
```

---

## Como reverter (rápido) se algo der errado

* Se você ainda tem a sessão original aberta, restaure o backup automático do `sshd_config` e reinicie:

```bash
sudo cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
sudo systemctl restart sshd
```

* Se você já fechou a sessão e não consegue conectar, use o **VNC/Console** do seu provedor ou o modo Rescue para reverter os passos (restaurar arquivo `sshd_config`, copiar a chave para `/root/.ssh/authorized_keys`, habilitar `PasswordAuthentication` temporariamente).

---

## Troubleshooting rápido

* **`Permission denied (publickey)`**: verifique se a chave pública correta está em `/root/.ssh/authorized_keys` (ou em `/home/USER/.ssh/authorized_keys`) e se as permissões estão certas:

```bash
sudo chown -R root:root /root/.ssh
sudo chmod 700 /root/.ssh
sudo chmod 600 /root/.ssh/authorized_keys
```

* **`Connection refused`**: SSH não está rodando (`systemctl status sshd`) ou firewall bloqueando (ver `ufw status`).

* **Ao trocar porta SSH**: sempre use `ssh -p PORT ...` ao testar.

* **Se `sshd` não reinicia por erro de configuração**: restaure o backup do `sshd_config` e reinicie como mostrado acima.

---

## Boas práticas (após o hardening)

* Mantenha a chave privada segura e com passphrase.
* Não exponha serviço VNC publicamente. Use VNC apenas via painel do provedor quando necessário.
* Considere desabilitar completamente `PermitRootLogin` (`PermitRootLogin no`) depois de confirmar que o usuário sudo funciona.
* Configure backups e monitoração (logs, alertas).

---

## Observações finais

Este arquivo é a documentação mínima para lembrar o que aquele script fez e como agir caso algo dê errado. Se for usar em produção, faça um teste em uma VM de staging antes.

Se estiver em dúvida, volte para este documento e siga os passos de verificação e reversão.

---

Gerado para você. Boa sorte — e lembra: sempre mantenha uma sessão aberta para testar antes de encerrar a sessão original.
