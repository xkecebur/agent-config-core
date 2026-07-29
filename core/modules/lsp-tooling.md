---
name: lsp-tooling
description: Language server setup and operational reference for Java, Go, Python, Bash, Docker, YAML/Kubernetes, PostgreSQL, and PHP — which server handles which language, known limitations, installation, and troubleshooting. Use when a language server misbehaves, when adding or changing one, or when you need to know a specific limitation.
alwaysApply: false
---

# Language Server Tooling

The usage rule ("prefer the language server over text search") belongs in the
constitution. This module is the operational detail.

## Reference setup

| Language | Server | Install | Extensions |
|---|---|---|---|
| Java | `jdtls` (Eclipse JDT.LS, needs JDK 17+) | distribution package | `.java` |
| Go | `gopls` | `go install golang.org/x/tools/gopls@latest` | `.go` |
| Python | `pyright-langserver` | `npm i -g pyright` | `.py`, `.pyi` |
| Bash | `bash-language-server` | `npm i -g bash-language-server` | `.sh`, `.bash` |
| Docker | `docker-langserver` | `npm i -g dockerfile-language-server-nodejs` | `Dockerfile` |
| YAML / K8s | `yaml-language-server` | `npm i -g yaml-language-server` | `.yaml`, `.yml` |
| PostgreSQL | `postgrestools lsp-proxy` | `npm i -g @postgrestools/postgrestools` | `.sql` |
| PHP | `intelephense --stdio` | `npm i -g intelephense` | `.php` |

One command for the npm-based servers:

```bash
npm i -g pyright bash-language-server dockerfile-language-server-nodejs \
  yaml-language-server @postgrestools/postgrestools intelephense
```

## Known limitations

- **jdtls** — the first index of a project is slow because it builds the classpath. Wait for
  it to finish before trusting `findReferences`.
- **yaml-language-server** — runs as a generic YAML server (syntax and structure).
  Kubernetes schema validation is not fully active unless the host exposes a
  `yaml.schemas` setting for schema association; many agent integrations do not.
- **postgrestools** — syntax checking works with no database connection. Context-aware
  completion (table and column names) needs a `postgrestools.jsonc` with a connection
  string at the project root.

## Troubleshooting

1. No diagnostics at all → confirm the binary is on `PATH` (`command -v gopls`)
2. `findReferences` returns nothing for a symbol that is clearly used → indexing is not
   finished (Java), or the file sits outside the project root
3. Configuration changed but nothing happened → most integrations require restarting the
   agent session after changing enabled servers

## When to reach for the language server instead of text search

- Locating a symbol definition rather than guessing a file path
- Finding every reference before a refactor — avoids grep false positives
- Checking diagnostics and type information before claiming work is finished
- Semantically safe cross-file renames
