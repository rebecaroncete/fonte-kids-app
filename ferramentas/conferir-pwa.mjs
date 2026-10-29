// Conferência do app instalável (rodar na raiz do repositório):
//   node ferramentas/conferir-pwa.mjs
// Confere: (1) VERSAO de app/sw.js = número da versão em app/config.js;
//          (2) todo arquivo de app/ está na lista ARQUIVOS do sw.js (e vice-versa).
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const APP = "app";
const sw = readFileSync(join(APP, "sw.js"), "utf8");
const config = readFileSync(join(APP, "config.js"), "utf8");

const versaoSw = sw.match(/const VERSAO = "([^"]+)"/)?.[1];
const versaoConfig = config.match(/versao:\s*"([0-9.]+)/)?.[1];
const lista = [...sw.match(/const ARQUIVOS = \[([\s\S]*?)\];/)[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);

const IGNORAR = new Set(["README.md", "sw.js"]);
function arquivos(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? arquivos(p) : [relative(APP, p).split("\\").join("/")];
  });
}
const noDisco = arquivos(APP).filter((f) => !IGNORAR.has(f));

let ok = true;
if (versaoSw !== versaoConfig) { ok = false; console.log(`✗ Versões diferentes: sw.js ${versaoSw} × config.js ${versaoConfig}`); }
for (const f of noDisco) if (!lista.includes(f)) { ok = false; console.log(`✗ Falta no sw.js: ${f}`); }
for (const f of lista) if (f !== "./" && !existsSync(join(APP, f))) { ok = false; console.log(`✗ No sw.js mas não existe: ${f}`); }
console.log(ok ? `✓ Tudo certo (versão ${versaoSw}, ${lista.length} arquivos).` : "Corrija os itens acima antes de publicar.");
process.exit(ok ? 0 : 1);
