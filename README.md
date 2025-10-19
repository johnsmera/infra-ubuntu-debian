# Harden SSH — Guia rápido 
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
* Reinicia o serviço OpenSSH depois de validar a configuração (**nota importante sobre o nome do serviço** logo abaixo).
* Reseta e configura UFW: `deny incoming` por padrão, permite saída, permite + rate-limit na porta SSH escolhida.
* Cria configuração básica do `fail2ban` para proteger logins SSH.
* Habilita updates automáticos via `unattended-upgrades`.

> ⚠️ **Ubuntu vs Debian — nome do serviço**
>
> * Em **Ubuntu** o unit costuma se chamar **`ssh.service`**.
> * Em **Debian** (ou derivados), às vezes aparece como **`sshd.service`**.
> * Use os comandos abaixo que **testam ambos**.

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

1. Em outro terminal, teste com a chave (ajuste porta se tiver mudado):

```bash
ssh -i ~/.ssh/id_ed25519 root@SEU_IP
# ou, se criou deploy e trocou porta
ssh -p 2222 -i ~/.ssh/id_ed25519 deploy@SEU_IP
```

2. Verifique status do OpenSSH (tente ambos os nomes, Ubuntu e Debian):

```bash
sudo systemctl status ssh --no-pager -l || sudo systemctl status sshd --no-pager -l
```

3. Verifique se UFW está ativo e regras:

```bash
sudo ufw status verbose
```

4. Verifique fail2ban (cadeia de proteção pro SSH):

```bash
sudo systemctl status fail2ban --no-pager -l
sudo fail2ban-client status sshd
```

> Observação: o jail padrão do fail2ban chama-se `sshd` mesmo quando o serviço systemd é `ssh` — está correto assim.

---

## Como reverter (rápido) se algo der errado

* Se você ainda tem a sessão original aberta, restaure o backup automático do `sshd_config` e reinicie o OpenSSH (testando os dois nomes de unidade):

```bash
sudo cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
sudo systemctl restart ssh || sudo systemctl restart sshd
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

* **`Connection refused`**: OpenSSH não está rodando ou porta errada. Veja status (testando ambos):

```bash
sudo systemctl status ssh --no-pager -l || sudo systemctl status sshd --no-pager -l
```

* **Ao trocar porta SSH**: sempre use `ssh -p PORT ...` ao testar.

* **Validar sintaxe da config** (útil antes de reiniciar):

```bash
sudo /usr/sbin/sshd -t || sudo sshd -t
```

Se houver erro, restaure o backup do `sshd_config` e reinicie:

```bash
sudo cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
sudo systemctl restart ssh || sudo systemctl restart sshd
```

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

Atualizado para refletir o nome do serviço no **Ubuntu (`ssh`)** e em alguns **Debian/derivados (`sshd`)**.
