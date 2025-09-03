# Windows no Docker

Este projeto é um contêiner Docker para executar Windows em um ambiente Linux. O objetivo principal é **facilitar a geração de executáveis Windows a partir de uma máquina Linux**, eliminando a necessidade de ter um sistema Windows físico ou máquina virtual dedicada.

Baseado no projeto [dockurr/windows](https://github.com/dockurr/windows).

## Objetivo Principal

**Gerar executáveis Windows (.exe) em uma máquina Linux** de forma simples e eficiente, especialmente útil para desenvolvedores que trabalham principalmente em Linux mas precisam criar aplicações para Windows.

## Como Usar

Para executar o contêiner, execute o seguinte comando:

```bash
docker-compose up
```

O Windows estará disponível em `http://localhost:8006`.

## Guia Completo: Gerando Executáveis Windows

### Pré-requisitos
- Docker e Docker Compose instalados no Linux
- Código Ruby que você deseja compilar para executável Windows

### Passo a Passo

1. **Iniciar o ambiente Windows**
   ```bash
   docker-compose up
   ```

2. **Acessar o Windows**
   - Abra seu navegador e vá para `http://localhost:8006`
   - Aguarde o Windows inicializar completamente

3. **Configurar o ambiente Ruby no Windows**
   - Instalar o Ruby e o Ruby DevKit
   - Instalar a gem `ocran`:
     ```cmd
     gem install ocran
     ```

4. **Gerar o executável**
   - **IMPORTANTE**: Copie seus arquivos Ruby para um diretório Windows nativo (ex: `C:\temp\`)
   - **NÃO** execute no diretório compartilhado com o host Linux
   - Execute o comando:
     ```cmd
     ocran <arquivo.rb> --add-all-core
     ```

### Vantagens desta Solução

- ✅ Não precisa de Windows físico ou VM dedicada
- ✅ Ambiente isolado e limpo
- ✅ Fácil de configurar e usar
- ✅ Ideal para CI/CD e automação
- ✅ Reutilizável para múltiplos projetos

### Observações Importantes

- O executável deve ser gerado em um diretório Windows nativo para funcionar corretamente
- O diretório compartilhado entre host e contêiner pode causar problemas na compilação
- Certifique-se de que todas as dependências estão incluídas no executável

