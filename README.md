# Microsoft Live: tres demos de busqueda de tutoriales

Una demo reproducible de **.NET + Azure AI Search + MCP + Copilot Studio**.
El mismo servicio de busqueda se utiliza desde la API REST y la herramienta MCP
`buscar_tutoriales`. Sin LLM en el backend: recupera tutoriales, no inventa respuestas.

> El catalogo contiene **13 documentos sinteticos**. Sus enlaces `example.invalid`
> no son tutoriales publicados ni navegables. Es una demostracion tecnica, no un
> buscador de documentacion real ni un servicio de produccion.

## Las tres demos

| Demo | Que se muestra | Para reproducir |
| --- | --- | --- |
| **1. Local** | HTTP protegido, busqueda determinista, resultados y correlacion, sin Azure | .NET SDK y PowerShell; no claves ni cuenta cloud |
| **2. Azure + Postman MCP** | MCP real: initialize, tools/list y tools/call sobre Azure AI Search; pruebas 401 | Tu propio despliegue Azure, Postman Desktop y tu propia API key |
| **3. Copilot Studio + MCP** | Un agente descubre y consume buscar_tutoriales | Tu entorno Copilot Studio, orquestacion generativa y politica DLP compatible |

**Estado honesto:** el MCP remoto y REST se verificaron en Azure. En el entorno
del presentador, Copilot Studio **bloqueo la conexion por la politica DLP
`PowerApps Policy without CDS`**. La demo 3 explica el bloqueo y los pasos para
probarla en tu entorno; **no se presenta como una integracion validada**.

## Empieza en tu ordenador (demo 1)

Prerequisitos: Git, [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
y [.NET SDK 10.0.401](https://dotnet.microsoft.com/download/dotnet/10.0),
fijado en [global.json](global.json). No necesitas Node, MCPEE, Docker ni Azure.
Ejecuta desde PowerShell:

```powershell
git clone https://github.com/Sertxito/microsoft-live.git
Set-Location microsoft-live
dotnet restore Harness.sln
dotnet build Harness.sln --no-restore
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "container apps"
```

**Que hace cada paso:** `git clone` descarga el codigo; `Set-Location` entra en
el proyecto; `dotnet restore` descarga sus dependencias; `dotnet build` compila
sin repetir la restauracion. Hasta aqui no hemos demostrado una busqueda.
`demo-local.ps1` ejecuta la API en memoria y envia peticiones HTTP reales al
host de pruebas: permite observar autenticacion, busqueda y trazabilidad.
No imprime una respuesta guardada ni crea recursos Azure.

Esperado: liveness 200, acceso anonimo 401, readiness autorizada 200 y
`tutorial-001`, fuente, correlacion y `generatedAnswer: null`.
El host de esta demo es **en memoria**, con JWTs efimeros exclusivos de pruebas;
no es un servidor abierto que puedas llamar desde Postman.

```powershell
# Validacion completa
pwsh -NoProfile -File scripts\validate-local.ps1

# Otras consultas
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "microsoft foundry"
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "zzzznonexistent"
```

La restauracion descarga las dependencias declaradas de NuGet. No se instala
ninguna herramienta automaticamente. El proyecto usa net10.0 y warnings-as-errors.
Los scripts y el despliegue se verificaron en Windows + PowerShell 7.

La publicacion se comprobo en una carpeta nueva con **solo los archivos publicos**:
restore/build, **119 pruebas correctas**, demo Container Apps (`tutorial-001`)
y demo Foundry (`tutorial-013`). No depende del estado privado del autor.

## Guia explicativa y prompts para copiar

La **[guia de las tres demos](docs/demo/GUION-DEMO.md)** contiene pasos,
consultas copiables, que hace cada comando, por que importa cada comprobacion
y que no demuestra. El [mapa de scripts Azure](docs/demo/AZURE-EN-TU-CUENTA.md#que-hace-cada-script)
explica tambien los pasos de infraestructura, permisos, datos y promocion.

## Demo 2: tu Azure y Postman

1. Sigue **[Azure en tu cuenta](docs/demo/AZURE-EN-TU-CUENTA.md)**.
   No reutilices IDs, claves o permisos del presentador.
2. Importa **[la coleccion MCP de Postman](demo/postman/tutorial-search-mcp.postman_collection.json)**.
3. Variable `baseUrl`: tu URL HTTPS, **sin `/mcp` y sin barra final**.
4. En **Postman Vault**, crea `apiKey` con tu clave. La coleccion usa
   `{{vault:apiKey}}` en el header `X-API-Key`; no exportes ni sincronices la clave.
5. En Postman Desktop, envia 01-07 en orden. La 04 debe devolver `tutorial-001`;
   06/07 deben devolver 401. La notificacion 02 devuelve 202, no 200.

Los tests interpretan respuestas JSON y el sobre SSE de **Streamable HTTP**;
no se usa el transporte SSE antiguo. Para la REST alternativa tienes
[otra coleccion](demo/postman/tutorial-search-api-key.postman_collection.json).
Postman demuestra disponibilidad del endpoint/protocolo en ese momento, no
garantiza disponibilidad futura ni evita las politicas de Copilot Studio.

## Demo 3: Copilot Studio

**Herramientas > Nueva herramienta > Model Context Protocol**:

- Nombre: `Tutoriales Microsoft`.
- URL: `https://<tu-host-de-container-apps>/mcp`.
- Autenticacion: **API key > Header > X-API-Key**.
- Activa orquestacion generativa y crea la conexion con tu clave.
- No necesitas Swagger para el asistente nativo MCP.

Descripcion y prompts: [guia de las demos](docs/demo/GUION-DEMO.md).
Configuracion completa: [conexion MCP](docs/integration-mcp-copilot-studio.md).
Si DLP lo bloquea, la persona administradora debe revisar la politica que afecta
al entorno y autorizar el conector/endpoint de forma acotada. Tener una cuenta
personal o ser Owner en Azure **no concede** administracion de Power Platform.
No se recomienda desactivar todas las protecciones ni buscar un bypass.

## Arquitectura y limites

```text
Demo local / REST / MCP -> TutorialSearchSpecialist
                           |-- LocalDeterministic: JSON sintetico
                           `-- AzureIntegrated: Azure AI Search + managed identity
Copilot Studio -> Streamable HTTP /mcp -> buscar_tutoriales
```

- `/health/live`: publico y minimo.
- `/health/ready`, `/api/capabilities`, `/api/tutorials/search`, `/mcp`: protegidos.
- JWT por defecto; la demo Azure elige explicitamente API key de 256 bits.
- Query 3-200 caracteres, 1-5 resultados, audience `community`, sin respuesta generada.
- Limite compartido de 30 peticiones/minuto por instancia y deadline de busqueda de 5 s.
- MCP stateless; sin comandos de terminal, discovery anonimo ni fallback de autenticacion.
- Container Apps 0-1 replicas: **puede haber cold starts y timeouts**.
- HTTPS y allow-list IPv4; las IPs de conectores Microsoft son compartidas,
  no aislamiento por tenant. Clave solo en Vault/conexion/secretos.

Azure crea ACR Basic, Search Basic, Blob privado, Container Apps y monitorizacion.
Referencia orientativa verificada el 2026-11-06: **~70,76 EUR/mes de base** mas uso;
no es un presupuesto garantizado y puede cambiar. Scale-to-zero no elimina el
coste fijo de Search/ACR. Inspecciona y elimina manualmente **solo tu grupo de
demo aislado** cuando termines; este repositorio no ejecuta limpieza automatica.

## Documentacion y evidencia

- [Indice](docs/README.md), [arquitectura](docs/architecture.md), [seguridad](docs/security.md).
- [Guia explicativa de las tres demos](docs/demo/GUION-DEMO.md).
- [Despliegue en tu cuenta](docs/demo/AZURE-EN-TU-CUENTA.md).
- [Postman](docs/integration-postman.md), [MCP y Copilot Studio](docs/integration-mcp-copilot-studio.md).
- [Pruebas y alcance de las verificaciones](docs/verification-matrix.md).
- [Versiones](docs/versions.md), [infraestructura](infra/).

No se publican claves, estado Azure local, historial/especificaciones privadas
MCPEE ni dependencias que apunten al ordenador del autor. **MCPEE no es el MCP
de esta demo** y no hace falta para reproducirla. Los hosts del presentador que
aparecen en la evidencia historica no son un servicio publico con acceso garantizado;
usa tu propio despliegue y nunca solicites su clave.
