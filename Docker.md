# 🐳 Instalação do Docker + Docker Compose V2 (Ubuntu 24+)

Este guia mostra como instalar o Docker Engine e o Docker Compose V2 (plugin oficial), configurar permissões e testar a instalação.

---

## 1. 🧼 Remover versões antigas (opcional, mas recomendado)

```bash
sudo apt-get remove docker docker-engine docker.io containerd runc -y
```

---

## 2. 🧰 Instalar dependências necessárias

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
```

---

## 3. 🐳 Adicionar chave oficial GPG do Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

---

## 4. 🧭 Adicionar repositório oficial do Docker

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

---

## 5. 📦 Instalar Docker Engine + CLI + Compose V2

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## 6. 🧪 Testar instalação do Docker

```bash
sudo docker run hello-world
```

Se você ver a mensagem **“Hello from Docker!”**, está funcionando ✅

---

## 7. 👤 (Opcional) Adicionar seu usuário ao grupo `docker`

Assim você pode usar `docker` sem `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

> ⚠️ Você precisa **sair e entrar novamente na sessão** (ou usar `newgrp docker`) para aplicar.

---

## 8. 🧱 Verificar versão do Docker e Compose

```bash
docker --version
docker compose version
```

Saída esperada (ou similar):

```
Docker version 27.x.x, build ...
Docker Compose version v2.x.x
```

---

## 9. 🧭 Habilitar Docker para iniciar com o sistema

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

Verificar status:

```bash
sudo systemctl status docker
```

---

## 10. 🐙 Testar Docker Compose V2

Crie um arquivo `docker-compose.yml` simples:

```yaml
services:
  hello:
    image: hello-world
```

Execute:

```bash
docker compose up
```

Você deverá ver a mensagem “Hello from Docker!” via Compose também.

---

## 🚀 Dica extra: atualizar Docker no futuro

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

Ou manualmente:

```bash
sudo apt-get install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## ✅ Pronto!

* Docker e Compose V2 instalados.
* Serviço habilitado no boot.
* Usuário configurado (se aplicável).
* Tudo pronto para subir containers e stacks.
