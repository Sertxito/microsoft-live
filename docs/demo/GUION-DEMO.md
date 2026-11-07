# Guion facil: las tres demos

## Antes de salir a escena

- Clona el repositorio y ejecuta restore/build de [README](../../README.md).
- Abre tres ventanas: PowerShell, Postman Desktop y Copilot Studio.
- Para Azure, utiliza tu propia cuenta y [despliegue](AZURE-EN-TU-CUENTA.md).
- Carga la [coleccion MCP](../../demo/postman/tutorial-search-mcp.postman_collection.json).
- Guarda `apiKey` en Postman Vault; `baseUrl` = tu host HTTPS sin `/mcp`.
- No proyectes valores de secretos ni la consola HTTP con headers de autenticacion.
- Prueba antes de la presentacion. No hagas mas de 30 solicitudes/minuto.

## Demo 1 - Local, sin Azure (3 minutos)

**Di:**
> Primero pruebo el mismo servicio de busqueda sin cloud ni modelo.
> El catalogo es sintetico: los enlaces son datos de prueba.
> La API verifica autenticacion; no la hemos desactivado para la demo.

**Copia en PowerShell, desde la raiz:**

```powershell
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "container apps"
```

**Muestra:** liveness 200, anonimo 401, readiness autorizada 200; resultado
`tutorial-001`, source, correlationId y `generatedAnswer: null`.
Son JWTs exclusivos del host de pruebas en memoria; no son claves de Azure.

```powershell
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "microsoft foundry"
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "zzzznonexistent"
```

**Esperado:** `tutorial-013` para Foundry; lista vacia para la consulta inexistente.
Sin resultados no significa inventar una respuesta.

**Cierre:**
> Hemos probado busqueda, autenticacion y correlacion. Ahora cambiamos el
> proveedor a Azure, sin duplicar la logica.

## Demo 2 - Azure + Postman: MCP real (5 minutos)

**Di:**
> Esto no es una llamada REST disfrazada de MCP. Vamos a negociar el protocolo,
> descubrir una herramienta y ejecutarla en el backend desplegado.

En Postman Desktop, envia las peticiones en este orden:

| Peticion | Lo que ensenar | Resultado esperado |
| --- | --- | --- |
| 01 Inicializar MCP | JSON-RPC initialize y capabilities.tools | 200, protocolo 2025-03-26 |
| 02 Confirmar inicializacion | notifications/initialized | 202, sin cuerpo de respuesta necesario |
| 03 Listar herramientas | tools/list, nombre y esquema | solo buscar_tutoriales |
| 04 Buscar tutoriales | tools/call y structuredContent | tutorial-001, fuente, correlacion, generatedAnswer null |
| 05 Argumento invalido | query de dos caracteres | 200 con isError true y validation_error |
| 06 Sin clave | discovery sin credencial | 401 |
| 07 Clave incorrecta | no hay fallback | 401 |

Abre los **Post-response test results** para ensenar las comprobaciones.
Si el sobre es `text/event-stream`, el resultado JSON esta en la linea `data:`;
sigue siendo MCP Streamable HTTP, no el transporte legacy SSE.

**Body copiable de la busqueda (POST a tu `/mcp`):**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "buscar_tutoriales",
    "arguments": {
      "query": "container apps",
      "maxResults": 1,
      "audience": "community"
    }
  }
}
```

Headers ya preparados en la coleccion: Content-Type application/json,
Accept application/json, text/event-stream, MCP-Protocol-Version 2025-03-26.
X-API-Key se toma de Vault. No copies la clave en el body.

**Cierre:**
> Azure y el MCP responden; la herramienta recupera datos y exige una clave.
> Esto prueba el endpoint en este momento. No prueba por si solo Copilot Studio.

**Si falla:** muestra el codigo. 401 = credencial; 403 sin correlacion puede ser
allow-list/IP de salida; 408/timeout puede ser arranque/dependencia.
Tras confirmar la causa, haz un reintento deliberado, no una cadena automatica.
Usa el cliente Desktop: el runner cloud de Postman puede salir de otra IP.

## Demo 3 - Copilot Studio + MCP (3-5 minutos)

**Di desde el principio:**
> En mi entorno la politica DLP "PowerApps Policy without CDS" bloqueo la
> creacion de la conexion. No voy a presentar ese paso como exitoso.
> El MCP se ha comprobado por separado. Cada uno puede probar la conexion
> en su propio entorno con los permisos y politicas adecuados.

1. Activa orquestacion generativa.
2. Herramientas > Agregar herramienta > Nueva herramienta > Model Context Protocol.
3. Nombre: **Tutoriales Microsoft**.
4. URL: **tu host HTTPS con `/mcp`**.
5. API key > Header > **X-API-Key**.
6. Crea la conexion con la clave solo en su formulario protegido.
7. Anade la herramienta descubierta buscar_tutoriales.

**Descripcion del servidor para copiar:**

```text
Busca tutoriales sobre tecnologias Microsoft en un catalogo de demostracion.
Devuelve titulos, resumenes y fuentes mediante buscar_tutoriales.
Los enlaces son sinteticos; no genera respuestas ni verifica documentacion externa.
```

**Instrucciones del agente (anadir sin sustituir sus reglas de seguridad):**

```text
Cuando el usuario pida tutoriales Microsoft, utiliza buscar_tutoriales.
Pasa su consulta en query, maxResults 5 y audience community.
Presenta los titulos, resumenes y fuentes devueltos.
Advierte que el catalogo y los enlaces son sinteticos.
No inventes tutoriales ni afirmes haber abierto o verificado los enlaces.
Si no hay resultados, dilo. Si la herramienta falla, explica el fallo;
no lo sustituyas por resultados imaginados.
```

**Prompts para pegar en el chat del agente:**

```text
Busca tutoriales sobre Container Apps. Usa la herramienta y muestra titulo,
resumen y fuente. Aclara que los enlaces pertenecen a una demo sintetica.
```

```text
Busca tutoriales sobre Microsoft Foundry y devuelve como maximo cinco resultados.
```

```text
Busca tutoriales sobre zzzznonexistent. Si no hay resultados, dilo sin inventarlos.
```

**Si aparece DLP:** ensena el mensaje con el nombre de la politica.
Una persona administradora de Power Platform debe revisar su alcance y permitir
especificamente el conector/endpoint segun la politica de su tenant.
Ser propietario de Azure o tener cuenta personal no concede ese rol.
No desactives la politica completa ni uses Postman para eludirla en Copilot Studio:
Postman es una comprobacion independiente del backend.

**Cierre final:**
> Misma logica de busqueda, tres superficies: prueba local, MCP remoto y agente.
> El repositorio permite reproducirlo en tu equipo y tu cuenta. El paso de
> Copilot Studio depende de la configuracion de tu entorno.
