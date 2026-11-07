# Guion facil: las tres demos

## La idea que queremos demostrar

No es "ejecuto un script y sale verde". Es **seguir una consulta desde el cliente
hasta los datos y entender donde puede fallar**:

1. Local: demostrar el comportamiento de la API sin depender de Azure.
2. Azure + Postman: comprobar ese backend remoto y el contrato MCP sin un agente.
3. Copilot Studio: conectar un agente que decide llamar a la herramienta;
   esa decision y su respuesta final son otra capa, no parte del buscador.

En cada paso explica **que entra, que se ejecuta, que sale y que conclusion
permite sacar**. Estar preparado hace la demo repetible; no sustituye la evidencia.
Los datos y resultados esperados son sinteticos y conocidos, no una prueba de
calidad sobre cualquier tema ni sobre documentacion real.

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

**Antes de pulsar Enter, explica el comando:**
> `pwsh` ejecuta PowerShell 7. `-NoProfile` evita cargar mis personalizaciones
> de consola. `-File` selecciona el script y `-Query` le pasa la consulta.
> El script lanza el programa de demo ya compilado con `dotnet run --no-build`.
> Ese programa arranca la API ASP.NET en memoria, crea un cliente anonimo y
> otro con JWT de pruebas, y envia la consulta al endpoint de busqueda.
> La respuesta se calcula ahora sobre el JSON del catalogo; no es una captura.

Puedes abrir [el script](../../scripts/demo-local.ps1) y
[el programa que ejecuta](../../tests/Harness.LocalDemo/LocalDemo.cs) para mostrarlo.
El script no instala dependencias, no compila, no despliega y no abre un puerto
para Postman. Por eso restore/build van antes.

**Muestra:** liveness 200, anonimo 401, readiness autorizada 200; resultado
`tutorial-001`, source, correlationId y `generatedAnswer: null`.
Son JWTs exclusivos del host de pruebas en memoria; no son claves de Azure.

| Salida | Como interpretarla y por que importa |
| --- | --- |
| Liveness 200 | El host atiende HTTP; no demuestra por si sola acceso al proveedor de busqueda. |
| Anonymous capabilities 401 | El cliente sin credencial no puede consultar esa ruta protegida; no hemos desactivado autenticacion para facilitar la demo. |
| Authorized readiness 200 | La API acepta el JWT de pruebas y su comprobacion de disponibilidad pasa en modo local. |
| HTTP 200 y tutorial-001 | La consulta devuelve un documento del catalogo; muestra titulo, resumen y fuente, no solo el codigo HTTP. |
| correlationId y Evidence | Permiten relacionar la respuesta con las etapas registradas para esa peticion, en lugar de adivinar donde se proceso. |
| generatedAnswer: null | El contrato devuelve recuperacion de documentos, no una respuesta redactada por un LLM. No acredita que los enlaces sean reales. |

**Di al leer el JSON:**
> El valor no es solo que responda 200: puedo identificar que dato recupero,
> de donde dice proceder y que peticion lo produjo. La linea Evidence muestra
> las etapas registradas de esta consulta. En cloud esa trazabilidad ayuda
> a investigar errores; aqui la estamos viendo en memoria.

```powershell
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "microsoft foundry"
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "zzzznonexistent"
```

**Esperado:** `tutorial-013` para Foundry; lista vacia para la consulta inexistente.
Sin resultados no significa inventar una respuesta.

**Por que cambiar la consulta:** conservamos el mismo endpoint y la misma logica,
pero modificamos la entrada. Foundry muestra otro documento; la consulta sin
coincidencias muestra una lista vacia. No vacies el catalogo para forzar el efecto.

**Si quieres ensenar la diferencia entre demo y validacion:**

```powershell
pwsh -NoProfile -File scripts\validate-local.ps1
```

> Este segundo script comprueba SDK/catalogo, recompila sin restaurar y ejecuta
> la suite de tests, guardando resultados TRX en TestResults. La demo anterior
> muestra estados y datos; no es por si sola una bateria de aserciones.
> Los tests verifican automaticamente mas escenarios que los tres que enseno.

El total verificado al publicar fue 119 pruebas. Una suite local verde **no prueba**
despliegue, permisos de Azure, red ni conexion desde Copilot Studio.

**Cierre:**
> Hemos probado busqueda, autenticacion y correlacion. Ahora cambiamos el
> proveedor a Azure, sin duplicar la logica.

## Demo 2 - Azure + Postman: MCP real (5 minutos)

**Di:**
> Esto no es una llamada REST disfrazada de MCP. Vamos a negociar el protocolo,
> descubrir una herramienta y ejecutarla en el backend desplegado.

**Explica que hemos preparado, sin ocultarlo:**
> Desplegar no equivale a cargar datos. La infraestructura crea Search, Blob,
> ACR y el entorno de ejecucion; otro script carga el catalogo; otro construye
> la imagen y otro crea la revision. La identidad del servicio puede leer Search,
> pero no cargar documentos. La API key autentica al cliente, no sustituye
> esa identidad interna. Ahora vamos a comprobar el recorrido completo.

Para explicar cada PowerShell de esa preparacion, usa el
[mapa de scripts](AZURE-EN-TU-CUENTA.md#que-hace-cada-script).
Postman envia peticiones al endpoint desplegado: no ejecuta esos scripts ni
necesita que el host de pruebas local siga abierto.

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

**Que aporta cada intercambio:**
- `initialize`: cliente y servidor acuerdan version/capacidades antes de usar herramientas.
- `notifications/initialized`: el cliente comunica que termino de inicializarse;
  202 es correcto porque una notificacion no lleva una respuesta JSON-RPC con resultado.
- `tools/list`: el cliente descubre el nombre, descripcion y esquema de entrada;
  no tiene que adivinar como se llama la herramienta.
- `tools/call`: envia argumentos, ejecuta la busqueda y devuelve datos estructurados.
  Comprueba el documento y los campos, no te quedes en el HTTP 200.
- Argumento invalido: distingue transporte correcto de ejecucion fallida.
  HTTP 200 puede contener `isError: true`; **no es una busqueda exitosa**.
- Sin clave/clave incorrecta: muestra que tambien el descubrimiento esta protegido;
  esas peticiones negativas estan preparadas sin la credencial valida a proposito.

Abre los **Post-response test results** para ensenar las comprobaciones.
Si el sobre es `text/event-stream`, el resultado JSON esta en la linea `data:`;
sigue siendo MCP Streamable HTTP, no el transporte legacy SSE.

La coleccion contiene 19 aserciones en siete peticiones. Son comprobaciones de
esta ejecucion contra un catalogo conocido, no tests de carga ni una garantia
de disponibilidad futura.

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

**Explica los argumentos antes de enviar:** `query` es el texto buscado;
`maxResults: 1` limita la respuesta a un documento; `audience: community` selecciona
la audiencia permitida en esta demo. `id: 4` relaciona la respuesta JSON-RPC con
esta llamada; no es el `correlationId` que genera el backend para trazabilidad.

**Si prefieres mostrar la comprobacion automatica desde PowerShell:**

```powershell
# Usa el host raiz, sin /mcp. apiKey debe estar ya en memoria; no la imprimas.
.\scripts\smoke-mcp.ps1 -BaseUri 'https://<TU-HOST>/' `
    -ApiKey $apiKey -AuthorizeRemote
```

El [script](../../scripts/smoke-mcp.ps1) anade `/mcp`, envia initialize,
notificacion, discovery, busqueda y casos negativos, y falla si el contrato no
coincide con lo esperado. `-AuthorizeRemote` confirma que autorizas esas llamadas:
**no despliega, no cambia trafico y no comprueba Copilot Studio**.
No lo ejecutes inmediatamente tras toda la coleccion si puedes superar el limite
compartido de 30 peticiones/minuto.

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

**Explica que cambia respecto a Postman:**
> En Postman yo decido exactamente que metodo y argumentos enviar.
> Aqui el agente recibe lenguaje natural y, mediante orquestacion generativa,
> puede decidir llamar a buscar_tutoriales. El backend sigue devolviendo datos,
> no una respuesta generada; el agente es quien puede redactar el mensaje final.
> Por eso una respuesta convincente en el chat no basta para probar la integracion.

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

**Si tu entorno permite la conexion:** muestra el detalle de ejecucion disponible
en Copilot Studio, confirma que se invoco `buscar_tutoriales` y revisa sus argumentos
y resultado. Compara despues el mensaje del agente con esos datos: titulos/fuentes
devueltos, advertencia sintetica y ausencia de tutoriales inventados.
Si no ves evidencia de llamada, no afirmes que el texto del chat demuestra uso de MCP.

**Si aparece DLP:** ensena el mensaje con el nombre de la politica.
Una persona administradora de Power Platform debe revisar su alcance y permitir
especificamente el conector/endpoint segun la politica de su tenant.
Ser propietario de Azure o tener cuenta personal no concede ese rol.
No desactives la politica completa ni uses Postman para eludirla en Copilot Studio:
Postman es una comprobacion independiente del backend.

**Valor del bloqueo para explicar arquitectura:**
> Hemos separado disponibilidad del backend de autorizacion del consumidor.
> Que MCP responda en Postman no significa que la politica del entorno permita
> crear la conexion en Copilot Studio. El fallo tiene una capa identificable;
> no se arregla recompilando ni quitando la clave de la API.

**Cierre final:**
> Misma logica de busqueda, tres superficies: prueba local, MCP remoto y agente.
> El repositorio permite reproducirlo en tu equipo y tu cuenta. El paso de
> Copilot Studio depende de la configuracion de tu entorno.
