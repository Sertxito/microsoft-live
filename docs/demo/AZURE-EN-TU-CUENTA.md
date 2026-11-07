# Reproducir Azure y MCP en tu cuenta

La demo local es gratuita respecto a Azure. Esta ruta **crea recursos facturables**:
Search Basic, ACR Basic, Blob privado, Container Apps y monitorizacion.
Referencia orientativa de la demo: ~70,76 EUR/mes de base mas uso (noviembre 2026);
consulta precios/cuotas actuales antes de desplegar. No hay un tope de gasto
garantizado y escalar la app a cero no deja de facturar Search/ACR.

No necesitas registrar aplicaciones consumidoras en Entra: esta ruta usa API key.
Las managed identities de Azure siguen siendo necesarias para Search y ACR.
No copies IDs, secretos o recibos de otra persona.

## Que hace cada script

Esta tabla es para entender la preparacion antes de copiar comandos.
**Comprobar, crear infraestructura, subir datos y aceptar una revision son
operaciones distintas**. Un paso correcto no acredita los siguientes.
Los enlaces permiten abrir el PowerShell real y seguir su implementacion.

| Script / accion | Que ejecuta y por que existe | Salida o evidencia; limite |
| --- | --- | --- |
| [validate-azure-local.ps1](../../scripts/validate-azure-local.ps1) | Analiza sintaxis PowerShell, compila los dos Bicep a ARM y comprueba reglas de seguridad, imagenes fijadas y esquema/catalogo. | Validacion local de la preparacion; no crea recursos ni demuestra cuotas, permisos o conectividad cloud. Requiere Azure CLI/Bicep disponibles. |
| [deploy-foundation.ps1](../../scripts/deploy-foundation.ps1) / Validate | Pide a Azure validar el template de infraestructura en tu grupo, despues de comprobar cuenta y grupo de demo. | Errores de validacion remota o resultado correcto; no despliega el servicio ni carga datos. |
| Mismo script / WhatIf | Pide a Azure calcular los cambios previstos a nivel de recursos. | Inventario para revisar antes de autorizar; una prevision no garantiza que el despliegue posterior termine bien. |
| Mismo script / Deploy | Despliega la base: Search, Blob, ACR, entorno Container Apps, monitorizacion, identidades y roles acotados. | Guarda nombres/IDs en `.local/azure/foundation.json`; aun no publica imagen, catalogo ni API. Crea recursos facturables. |
| [grant-demo-loader.ps1](../../scripts/grant-demo-loader.ps1) | Asegura tres roles acotados para el operador que carga datos, sin dar escritura al runtime. | Asignaciones RBAC; su existencia no garantiza propagacion inmediata ni una carga correcta. |
| [load-azure-knowledge.ps1](../../scripts/load-azure-knowledge.ps1) | Comprueba la identidad del operador y el esquema; crea el indice si falta, sube el JSON a Blob y hace mergeOrUpload de 13 documentos en Search. | Comprueba la aceptacion de cada documento; no borra documentos previos ni demuestra todavia una busqueda desde la API. |
| [build-azure-image.ps1](../../scripts/build-azure-image.ps1) | Sube una allow-list de fuentes a ACR y construye la imagen sin Docker local. | Devuelve referencia con digest SHA-256: identifica la imagen exacta, no solo un tag mutable. Tiene transferencia/coste y no la despliega. |
| [deploy-candidate.ps1](../../scripts/deploy-candidate.ps1) / Validate, WhatIf, Deploy | Valida/previsualiza o crea una revision con esa imagen, credencial elegida, identidad y acceso IPv4 /32; preserva el trafico aceptado en actualizaciones. | Guarda `.local/azure/candidate.json` al desplegar. Revision creada no significa busqueda verificada; el primer bootstrap no tiene predecesor. |
| [smoke-test.ps1](../../scripts/smoke-test.ps1) | Hace llamadas REST de salud, capacidades, busqueda y casos negativos; al promocionar comprueba tambien revision y modo Azure. | Evidencia de HTTP, autenticacion y contrato de recuperacion en ese momento; no verifica MCP ni cambia trafico. |
| [smoke-mcp.ps1](../../scripts/smoke-mcp.ps1) | Negocia MCP, descubre la herramienta, busca un documento conocido y prueba credenciales/argumentos invalidos. | Falla ante estados o datos inesperados; prueba protocolo y herramienta, no un agente, carga sostenida ni disponibilidad futura. |
| [set-demo-traffic.ps1](../../scripts/set-demo-traffic.ps1) / Promote | Ejecuta smoke REST nuevo y, si el candidate exige MCP, smoke MCP nuevo; revalida trafico y envia el 100% a la revision comprobada. | Guarda recibo `traffic-promote.json`; no confia solo en un smoke anterior ni elimina la revision previa. En bootstrap verifica/acepta la primera revision ya accesible. |
| [set-copilot-access.ps1](../../scripts/set-copilot-access.ps1) / Preview, Apply | Consulta rangos oficiales de conectores Europa; muestra o agrega los que faltan manteniendo HTTPS, autenticacion, trafico e imagen. | Guarda `.local/azure/copilot-access.json` tras verificar Apply. Permitir red no concede permisos Power Platform ni elimina bloqueos DLP. |

**Como leer los comandos:**
- `@context` y `@candidate` expanden tablas de parametros ya definidas en esta
  consola; no son archivos ni credenciales preconfiguradas del presentador.
- `-Action` elige la operacion del script. `Validate`/`WhatIf` remotos no son
  despliegues; `Deploy`, `Promote` y `Apply` si pueden modificar Azure.
- Los switches `-Authorize...` expresan consentimiento para llamadas, coste,
  subida de codigo/datos o cambios RBAC/red. No son permisos Azure: si tu cuenta
  carece del rol necesario, la operacion sigue fallando.
- Los JSON de `.local/azure` enlazan pasos con cuenta, recursos y revision exactos.
  No son respuestas de busqueda prefabricadas, no contienen la clave y no se publican.

Para presentar el valor: **infraestructura disponible -> datos cargados ->
imagen identificable -> revision comprobada -> consumo MCP -> agente permitido**.
Si un eslabon falla, muestra esa evidencia y no declares exitoso el recorrido entero.

## 0. Preparacion

- Completa restore/build del [README](../../README.md).
- Azure CLI con comandos Container Apps y Bicep disponibles; instala herramientas
  solo en tu equipo y con tu autorizacion. No necesitas Docker local: ACR construye.
- Permisos para crear el grupo/recursos y asignar roles en tu demo aislada.
  El operador que carga datos requiere tres roles acotados que se indican abajo.
- Region soportada por estos scripts: **West Europe**, no cambies solo una variable
  esperando que todos los guards/reglas regionales se adapten.
- Utiliza un grupo nuevo dedicado a esta demo, no un grupo compartido.
- Los comandos siguientes se ejecutan **en la misma PowerShell, desde la raiz**.
  Los switches Authorize son confirmaciones explicitas de operaciones con coste/
  transferencia/permisos, no un modo de simulacion.

```powershell
az login
az account list -o table

$subscriptionId = '<TU-SUBSCRIPTION-ID>'
az account set --subscription $subscriptionId
if ($LASTEXITCODE) { throw 'No se pudo seleccionar tu suscripcion.' }
$account = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE) { throw 'No se pudo comprobar tu cuenta.' }
$context = @{
    SubscriptionId = [guid]$account.id
    TenantId = [guid]$account.tenantId
}
$group = 'rg-microsoft-live-mi-demo'
$owner = 'mi-demo'

# Crear solo el grupo de demo antes del validate remoto.
az group create -n $group -l westeurope `
    --tags project=microsoft-live purpose=isolated-demo "owner=$owner" -o none
if ($LASTEXITCODE) { throw 'No se pudo crear el grupo aislado.' }
```

Para no modificar accidentalmente otro grupo, comprueba primero en el portal que
ese nombre no pertenece a recursos existentes. No uses los comandos con un grupo
compartido. Revisa las asignaciones de Azure Policy y las cuotas de tu suscripcion.

## 1. Validar y desplegar foundation

```powershell
.\scripts\validate-azure-local.ps1
.\scripts\deploy-foundation.ps1 @context -ResourceGroup $group -Owner $owner `
    -Action Validate -AuthorizeRemoteValidation
.\scripts\deploy-foundation.ps1 @context -ResourceGroup $group -Owner $owner `
    -Action WhatIf -AuthorizeRemoteValidation
```

Revisa la salida: grupo correcto, creaciones esperadas, ninguna eliminacion.
Si hay errores, arreglalos antes de continuar. Esta prevalidacion puede mostrar
datos de configuracion del grupo, pero no contiene la API key (aun no existe).

```powershell
.\scripts\deploy-foundation.ps1 @context -ResourceGroup $group -Owner $owner `
    -Action Deploy -AuthorizeAzureChanges -AuthorizeRbacChanges
$foundation = Get-Content .local\azure\foundation.json -Raw | ConvertFrom-Json
```

Puede tardar varios minutos. No lances otro despliegue en paralelo si sigue activo.
El recibo local contiene nombres/IDs, no tokens; preservalo y no lo publiques.

## 2. Dar permisos al operador y cargar el catalogo

Selecciona el **Object ID de tu usuario actual** en el tenant: Azure Portal >
Microsoft Entra ID > Usuarios > tu usuario > Id. Tener permiso sobre recursos
Azure no garantiza permisos para listar usuarios via Microsoft Graph.

```powershell
$operatorId = [guid]'<OBJECT-ID-DE-TU-USUARIO-EN-ESTE-TENANT>'
.\scripts\grant-demo-loader.ps1 @context -ResourceGroup $group `
    -PrincipalId $operatorId -PrincipalType User `
    -SearchName $foundation.searchName.value -StorageName $foundation.storageName.value `
    -AuthorizeRbacChanges
```

Solo otorga Search Service Contributor, Search Index Data Contributor en tu Search
y Storage Blob Data Contributor en su contenedor tutorials. El runtime no recibe
permisos de escritura. Puede requerir tiempo de propagacion; si falla la carga,
inspecciona permisos antes de reintentar.

```powershell
.\scripts\load-azure-knowledge.ps1 @context -ResourceGroup $group `
    -ExpectedLoaderPrincipalId $operatorId `
    -SearchName $foundation.searchName.value -StorageName $foundation.storageName.value `
    -AuthorizeDataUpload
```

Sube solo el catalogo sintetico a Blob y 13 documentos a Search.
No usa claves de almacenamiento/Search ni suplanta la managed identity del loader.

## 3. Construir la imagen en ACR

```powershell
$image = .\scripts\build-azure-image.ps1 @context -ResourceGroup $group `
    -RegistryName $foundation.registryName.value -AuthorizeSourceUpload
if ($image -notmatch '/harness@sha256:[a-f0-9]{64}$') {
    throw 'La construccion no devolvio un digest valido.'
}
$digest = $image.Split('@')[1]
```

El script sube una allow-list de codigo/configuracion/catalogo, no Git, pruebas,
historial MCPEE ni secretos. El resultado es una imagen inmutable Linux/amd64;
no copies el digest del presentador: construye tu propia imagen.

## 4. Tu clave y tu IP; candidate MCP

Genera tu clave solo en memoria y consulta la IP publica de **tu equipo**.
Esto hace una consulta a api.ipify.org; si no quieres usar ese servicio,
obtiene tu IPv4 por un medio de confianza y establece `$smokeCidr` manualmente.
Nunca uses 0.0.0.0/0 para evitar un error de acceso.

```powershell
$apiKey = [Convert]::ToHexString(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
$publicIp = (Invoke-RestMethod 'https://api.ipify.org?format=json').ip
$smokeCidr = "$publicIp/32"
$candidate = @{
    ResourceGroup = $group
    ImageDigest = $digest
    RevisionSuffix = 'mcp-demo01'
    SmokeClientCidr = $smokeCidr
    AuthMode = 'ApiKey'
    ApiKey = $apiKey
    RequireMcpSmoke = $true
    AuthorizeBootstrap = $true
}
.\scripts\deploy-candidate.ps1 @context @candidate -Action Validate -AuthorizeRemoteValidation
.\scripts\deploy-candidate.ps1 @context @candidate -Action WhatIf -AuthorizeRemoteValidation
```

Comprueba validacion correcta y ausencia de eliminaciones. Estos scripts usan
parametros secretos en un temporal protegido que borran al finalizar.
No imprimas `$candidate`, `$apiKey` ni pases la clave como literal en el historial.

```powershell
.\scripts\deploy-candidate.ps1 @context @candidate -Action Deploy -AuthorizeAzureChanges
$state = Get-Content .local\azure\candidate.json -Raw | ConvertFrom-Json
.\scripts\smoke-mcp.ps1 -BaseUri $state.baseUri -ApiKey $apiKey -AuthorizeRemote
.\scripts\set-demo-traffic.ps1 @context -Action Promote `
    -StatePath .local\azure\candidate.json -ApiKey $apiKey `
    -AuthorizeAzureChanges -AuthorizeRemoteSmoke
$candidate.ApiKey = $null
$apiKey = $null
```

Bootstrap no tiene predecesor y ya sirve esa primera revision solo dentro de su
allow-list; la promocion verifica y guarda su aceptacion. En cambios siguientes,
usa **otro suffix**, no AuthorizeBootstrap, preserva los recibos y el acceso;
mantiene la revision aceptada hasta que REST y MCP pasan de nuevo.
MCP smoke verifica initialize/list/call, wrong/missing key y argumento invalido.
Una primera llamada puede fallar por cold start; muestra el error, inspecciona
y reintenta deliberadamente sin ampliar deadlines o desactivar autenticacion.

## 5. Postman con tu URL y tu clave

En el portal: tu grupo > ca-m365live-demo > Informacion general > URL de aplicacion.
Usa el host **normal de la app**, no el host exclusivo de una revision.
En Secretos > api-key > Mostrar valor, copia tu clave directamente a **Postman Vault**,
nombre `apiKey`. No la publiques. Importa la
[coleccion MCP](../../demo/postman/tutorial-search-mcp.postman_collection.json),
establece `baseUrl` con tu HTTPS sin barra final y ejecuta 01-07.

Postman Desktop sale de la IPv4 autorizada de tu equipo. El runner cloud puede
estar bloqueado. Si cambia tu IP, revisa/autoriza el cambio de red por separado;
los scripts de candidate rechazan divergencias de la allow-list.

## 6. Permitir los conectores y probar Copilot Studio

Comprueba la **Geo del entorno Power Platform**; no es la region de la API.
El script siguiente admite **Europa** solamente. La Geo requiere North Europe
y West Europe para AzureConnectors y PowerPlatformPlex.
Las IPs Microsoft son compartidas: mantener la clave es obligatorio.

```powershell
.\scripts\set-copilot-access.ps1 @context -ResourceGroup $group -Action Preview
# Solo despues de revisar/autorizar las IPs oficiales compartidas:
.\scripts\set-copilot-access.ps1 @context -ResourceGroup $group -Action Apply `
    -AuthorizeNetworkChanges
```

Preserva `.local/azure/copilot-access.json`; futuros candidates lo utilizan.
Revisa los rangos al menos cada 90 dias; el script agrega los nuevos, no elimina
silenciosamente rangos antiguos. Para otra Geo, adapta/revisa las reglas oficiales
antes de ejecutar; no utilices esta allow-list Europa sin comprobar tu entorno.

Sigue [demo 3 del guion](GUION-DEMO.md) con **tu URL `/mcp`**.
Si DLP bloquea, requiere revision de la persona administradora de tu tenant.
La demo del presentador no supero ese bloqueo; no se afirma que tu tenant lo permita.

## 7. Terminar y controlar costes

Revisa en el portal la suscripcion/tenant, inventario, tags y dependencias del
**grupo aislado que tu creaste**. Cuando hayas terminado, elimina manualmente
solo ese grupo si no contiene recursos compartidos. Comprueba que no queden
recursos facturables/roles temporales. No hay script de borrado automatico.
No confundas la ausencia de replicas con la ausencia de coste.

Para una region, modelo de identidad o topologia diferente, usa la
[documentacion tecnica](../deployment.md) y revisa los guards de los scripts;
este quickstart no promete despliegue universal ni cuotas disponibles.
