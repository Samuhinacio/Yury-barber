# Barbearia Yury Peixoto · Sistema de agendamento online

Sistema de agendamento criado do zero por **Samuel Inácio José** para a Barbearia Yury Peixoto.
O cliente marca o horário sozinho, pelo celular, e o barbeiro acompanha a agenda, os clientes, a equipe e o financeiro em um painel com login.

- Site no ar: [yurybarber.netlify.app](https://yurybarber.netlify.app)
- Autor: Samuel Inácio José · [samuel-inacio-dev.netlify.app](https://samuel-inacio-dev.netlify.app)

> Esta é a versão pública do código, para consulta. Os dados de conexão com o banco de produção e a foto do barbeiro não estão incluídos.

## O que o sistema faz

**Site do cliente (`index.html`)**
- Escolha do barbeiro, do serviço, do dia e do horário, sem criar conta nem baixar aplicativo.
- Agenda inteligente: mostra só os horários livres e encaixa serviços curtos nas sobras da agenda.
- Forma de pagamento (Pix, dinheiro ou cartão) e aviso pronto para a barbearia no WhatsApp.

**Painel do barbeiro (`admin.html`)**
- Agenda do dia por barbeiro, atualizada em tempo real.
- Agendamento no balcão com sugestão de horários livres e situação do atendimento.
- Bloqueio de dias e de horários, com repetição semanal.
- Equipe com foto, ficha de clientes (frequentes e sumidos) e financeiro com a porcentagem da barbearia e os acertos.
- Serviços, preços e horário de funcionamento editáveis.

## Tecnologias

HTML, CSS e JavaScript (sem framework), Supabase (PostgreSQL, API REST, autenticação e tempo real), PL/pgSQL e Netlify.

## Arquivos

| Arquivo | Função |
| --- | --- |
| `index.html` | Página de agendamento do cliente |
| `admin.html` | Painel do barbeiro |
| `agenda.js` | Agenda inteligente (cálculo dos horários livres) |
| `banco-de-dados.sql` | Tabelas, regras de segurança e funções do banco |
| `config.js` | Endereço do banco e WhatsApp (em branco nesta versão) |
| `estilo.css` | Estilos compartilhados |

## Segurança

- Nome e telefone dos clientes só podem ser lidos por administradores autenticados (Row Level Security).
- O site público vê apenas quais horários estão ocupados.
- Cada agendamento é conferido no servidor (horário livre, funcionamento, preço), com trava contra dois clientes no mesmo horário e limite de horários por telefone.

## Direitos autorais

© 2026 Samuel Inácio José. **Todos os direitos reservados.**

O código está disponível apenas para consulta. Copiar, modificar, redistribuir ou usar este sistema, no todo ou em parte, depende de autorização prévia e por escrito do autor. Veja o arquivo [LICENSE](LICENSE).

O nome, a marca e o logotipo da Barbearia Yury Peixoto pertencem à barbearia.
