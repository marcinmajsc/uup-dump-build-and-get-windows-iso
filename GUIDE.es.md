# Guía: Cómo funciona el script uup-dump Windows ISO

## Resumen

Este script de PowerShell (`uup-dump-get-windows-iso.ps1`) automatiza el proceso de descarga de imágenes ISO de Windows usando la API de [UUP dump](https://uupdump.net). Obtiene metadatos, descarga el paquete de construcción apropiado y crea un ISO usable.

## Arquitectura

El script admite tres arquitecturas de CPU:

| Arquitectura | Mapeo | Descripción |
|-------------|-------|-------------|
| `x64` | `amd64` | Compatible x86 de 64 bits |
| `arm64` | `arm64` | de 64 bits ARM |
| `x86` (nuevo) | `x86` | de 32 bits x86 (añadido para compatibilidad de Windows 10 de 32 bits) |

## Compilaciones de Windows compatibles

El script define objetivos de compilación en un hashtable (`$TARGETS`) con cadenas de búsqueda que la API de UUP dump usa para encontrar compilaciones coincidentes. Cada entrada incluye:

- **search**: La consulta de búsqueda enviada a la API
- **edition**: El nombre de edición predeterminado (traducido mediante `Get-EditionName`)

### Compilaciones admitidas:

- `windows-10`: Windows 10 19045 (22H2)
- `windows-10-x86`: Windows 10 de 32 bits (x86) 19045 (22H2) - **nuevo**
- `windows-11old`: Windows 11 22631 (23H2)
- `windows-11`: Windows 11 26100 (24H2)
- `windows-11new`: Windows 11 26200 (25H2)
- `windows-11beta`: Windows 11 26120 (24H2 BETA)
- `windows-11dev`: Windows 11 26220 (25H2 BETA - canal Dev)
- `windows-1126h1`: Windows 11 28000 (26H1 - hardware nuevo)
- `windows-1126h2`: Windows 11 26300 (26H2)
- `windows-1126h2beta`: Windows 11 26340 (26H2 Experimental)
- `windows-dev`: Canal DEV de Windows 11
- `windows-canary`: Canal Canary de Windows 11

## Parámetros

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `windowsTargetName` | string | El nombre de la compilación (p. ej., `windows-11new`) |
| `destinationDirectory` | string | Directorio de salida (predeterminado: `output`) |
| `architecture` | string | `x64`, `arm64` o `x86` (predeterminado: `x64`) |
| `edition` | string | `pro`, `core`, `multi` o `home` (predeterminado: `pro`) |
| `lang` | string | Código de idioma (predeterminado: `en-us`) |
| `esd` | interruptor | Usar compresión ESD |
| `drivers` | interruptor | Agregar drivers (x64 y x86, no arm64) |
| `netfx3` | interruptor | Agregar .NET Framework 3.5 |
| `revision` | string | Número de revisión del sistema específico |

## Cómo funciona el script - Paso a paso

### 1. Procesamiento de parámetros e inicialización

El script comienza declarando todos los parámetros con conjuntos de validación para arquitectura e idioma. Luego:

- Modo estricto y configuración de preferencias de error
- Inicializa variables de seguimiento de progreso
- Determina si la compilación es una versión preview/beta/dev/canary
- Mapea el parámetro de arquitectura al formato interno (`x64` → `amd64`, `x86` → `x86`, `arm64` → `arm64`)

### 2. Búsqueda de objetivos

El script busca la compilación de Windows especificada en el hashtable `$TARGETS`. Esto devuelve metadatos que incluyen:

- La consulta de búsqueda para la API
- El nombre de edición
- Información de edición virtual (para algunas compilaciones)

### 3. Llamadas a la API de UUP dump

El script realiza varias llamadas a la API [https://api.uupdump.net](https://api.uupdump.net):

1. **`listid`**: Obtiene una lista de IDs de compilación que coinciden con la consulta de búsqueda
2. **`listlangs`**: Obtiene los idiomas disponibles para la compilación seleccionada
3. **`listeditions`**: Obtiene las ediciones disponibles para el idioma seleccionado

Estas llamadas incluyen lógica de reintentos (hasta 15 intentos con retrasos de 10 segundos) y manejo de errores.

### 4. Filtrado y selección

El script filtra los resultados según varios criterios:

- **Compilaciones preview**: Si no está en modo preview, filtra las compilaciones preview
- **Filtrado de ring**: Para compilaciones beta/dev/canary, valida la configuración de ring
- **Compatibilidad de idioma**: Asegura que el idioma seleccionado esté disponible
- **Compatibilidad de edición**: Valida que la edición coincida con la solicitada

### 5. Paquete de descarga

Después de seleccionar una compilación, el script:

- Construye el cuerpo de la solicitud de descarga según si hay ediciones virtuales involucradas
- Publica en la URL de paquete de descarga
- Guarda el paquete `.zip` en el directorio de compilación
- Extrae el paquete usando `Expand-Archive`

### 6. Configuración

El script modifica `ConvertConfig.ini` para controlar el proceso de creación del ISO:

- `AutoExit=1`: Salir después de la creación del ISO
- `ResetBase=1`: Restablecer la imagen base
- `Cleanup=1`: Limpiar archivos temporales
- `wim2esd=1` (si `-esd` bandera): Usar compresión ESD
- `AddDrivers=1` (si `-drivers` bandera): Agregar drivers de Dell
- `NetFx3=1` (si `-netfx3` bandera): Agregar .NET Framework 3.5
- Configuración de edición virtual (para compilaciones virtualizadas)

### 7. Ejecutando el archivo por lotes

El script parchea y ejecuta `uup_download_windows.cmd`, que usa [aria2](https://aria2.net/) para descargas. El script:

- Parchea las banderas de aria2 para operación silenciosa y registro reducido
- Ejecuta el archivo por lotes
- Captura la salida progresiva DISM/aria2 en bruto
- Analiza los cubos de progreso y muestra salida limpia
- Maneja errores y vierte los últimos 1500 líneas de registro en fallos

### 8. Finalización del ISO

Después de una compilación exitosa:

- Calcula la suma SHA256 del ISO
- Extrae la información de imágenes de Windows usando DISM (o adaptado para Linux)
- Crea archivo JSON de metadatos con detalles de la compilación
- Mueve el ISO al directorio de destino
- Envía `ISO_NAME` al entorno de GitHub para etiquetado de releases

## Detalles de compatibilidad con Linux

Al ejecutarse en PowerShell 7+ en Linux:

### Lo que funciona:

- Llamadas API a uup-dump.net (solicitudes HTTP)
- Descarga y extracción de paquetes ZIP
- Análisis de progreso (adaptado para diferentes formatos de registro)
- Generación de metadatos del ISO
- Cálculo de checksum

### Lo que requiere adaptación:

- **Montaje de ISO**: En Windows, usa `Mount-DiskImage`. En Linux, el script necesita 7-Zip o similar para extraer el contenido del ISO
- **Progreso DISM**: Los patrones de seguimiento de progreso se adaptan para salida estilo Linux
- **aria2**: La función `Patch-Aria2-Flags` incluye un respaldo de PowerShell cuando `sed` no está disponible
- **Administradores de paquetes**: En Linux, Chocolatey no está disponible; el script detecta administradores de paquetes del sistema

### Requerido para Linux:

- PowerShell 7+ instalado
- 7-Zip o equivalente para extracción de ISO
- aria2c para gestión de descargas
- Permisos apropiados para operaciones de disco

## Compatibilidad con Windows 7 / PowerShell 5.1

### Requisitos mínimos:

- PowerShell 5.1 (incluido en Windows 7/Server 2008 R2) o PowerShell 7+ (installable)

### Adaptaciones realizadas:

- `Get-FileHash` funciona en ambos PS 5.1 y PS 7+, con formato de salida compatible
- `ConvertTo-Json -Depth 99` se comporta de manera consistente en versiones
- Todos los patrones regex son independientes de cultura
- No depende de cmdlets DISM específicos de Windows para funcionalidad principal

### Limitaciones conocidas en PS 5.1:

- Algunas funciones avanzadas de seguimiento de progreso pueden no funcionar
- Formato de mensajes de error puede diferir
- Manejo de profundidad JSON puede tener diferencias menores

## Estructura de salida

Cuando el script finaliza exitosamente, produce:

1. **Archivo ISO**: El ISO de Windows en `<destino>/<ISO_NAME>.ISO`
2. **JSON de metadatos**: `<ISO_NAME>.json` que contiene:
   - Nombre de compilación, título, versión
   - Suma SHA256
   - Imágenes de Windows disponibles/indexes
   - URLs de API uup-dump
3. **Variable de entorno**: `ISO_NAME` configurado para integración de GitHub Actions

## Compilando paquetes de plataforma personalizados

La flujo de trabajo de GitHub Actions también compila paquetes específicos de plataforma:

- **Windows**: Script `.cmd` con aria2 y 7-Zip
- **Linux**: Script `.sh` con aria2 y 7-Zip
- **macOS**: Script shell con aria2 y 7-Zip

Estos paquetes contienen:
- Archivos binarios (aria2c, 7z)
- Scripts de descarga
- Lógica de extracción de partes
- Verificación de checksum

## Depuración

### Problemas comunes:

1. **Compilación no encontrada**: Verifique que el parámetro `windowsTargetName` coincida con una compilación admitida
2. **Idioma no disponible**: Verifique que el código de idioma esté en la lista admitida
3. **Mismatch de edición**: Asegúrese de que la edición exista para la compilación seleccionada
4. **Drivers no instalándose**: Drivers se omiten para arquitectura arm64
5. **Progreso no mostrando**: Puede ocurrir en Linux con diferentes formatos de registro
6. **Fallo en extracción ISO**: Asegúrese de que 7-Zip esté disponible o instálalo

### Modo debug:

El script incluye salida detallada mediante `Write-CleanLine` que elimina secuencias de escape ANSI. Establezca `$DebugPreference = 'Continue'` para información de depuración adicional.

## Consideraciones de seguridad

- El script descarga de APIs externas (uup-dump.net)
- Las descargas de ARIA2 se ejecutan con `--quiet=true` para reducir salida
- Checksums se proporcionan para verificación
- No se ejecutan scripts externos sin confirmación del usuario




ATENCION, AVISO (12 de octubre de 2026): microsoft cortara el acceso a partir
del 19 de junio del 2027 el acceso a windows update a todos los equipos que
tengan windows 10 sin ESU hacia abajo (el bloqueo anterior fue hasta windows
vista-server 2008 sin R2), esto logicamente afecta a las versiones de servidor
(server 2008 R2 hasta server 2019, a partir de server 2022, no afecta el cierre
de windows update), esto es debido a la caducidad de los certificados raiz
del servicio de actualizaciones que caduca a partir de esta fecha, si quieres
echar un vistazo al link oficial de la noticia de microsoft, aqui te lo paso (usa la traduccion del navegador, esta en ingles):

https://techcommunity.microsoft.com/blog/windows-itpro-blog/prepare-for-windows-update-certificate-rotation-in-2027/4562463

recuerda que los certificados raiz forman parte de la navegacion por internet, una de las caracteristicas del protocolo https
es que ahora todo lo que se transfiere al router esta cifrado (anteriormente no era asi), pero para que programas que se uti
lizan para analizar todo lo que se transfiere en una red domestica como wireshark no surta ningun efecto (no se vea ningun
dato sensible), los certificados raiz deben de funcionar y estar al dia, si no funciona, da error de certificado en el navegador
y los programas que conectan a internet dejaran de funcionar, esto lo tienes que tener en cuenta a la hora de utilizar un windows
antiguo instalado en el ordenador (por cierto, el cierre de windows update tambien afecta a las maquinas virtuales, o sea, a los PCs
arrancados dentro de un equipo fisico).

cuando llegue la fecha de caducidad del certificado raiz es posible que en los offices instalados en windows sin soporte den errores
de comprobacion de actualizaciones (hasta 10 y server 2019 que son cliente y servidor respectivamente se puede instalar el 2021-365
7 y 8, hasta office 2016), solucionandose esto desactivando las actualizaciones de office (cuando llegue la fecha de caducidad de
dichos certificados raiz).

en la ventana anterior (las actualizaciones automaticas se impusieron a partir de windows 2000) no dio ningun tipo de fallo a la
hora de arrancar el sistema operativo, unicamente a la hora de abrir la pagina de microsoft update o iniciar el windows update.
(pase la experiencia de la ventana anterior de cierre del update).

en el caso de que sea windows 10 con ESU, windows 11 24H2, servers LTSC de 2019 y 2016 y server 2022, microsoft ha puesto como
metodo oficial para solucionar el problema, la actualizacion, o sea, que tendras que actualizar el segundo martes de cada mes
hasta la fecha del 19 de junio de 2027 en el cual ya...piano, piano (entenderas lo que te digo).

en el caso de que te encuentres con este tipo de equipos, estos son los caminos que tienes:

-  comprar el ESU (windows 10) (en el caso de paises de la union europea, no tiene ningun coste) 
-  parchear el update para acceder al ESU, que el unico parche (y recomendable para windows 10) es el MAS (microsoft activation script)
-  instalar un parche no oficial para actualizar los certificados raiz, que es el legacy update
-  en el caso de versiones compatibles (no es obligatorio por el momento a partir de 11 24H2, windows 10 sin ESU es imprescindible
a medias) aceptar las actualizaciones a versiones mayores de windows via update o haciendo una actualizacion desde los medios de
instalacion de windows.
-  mantener la instalacion de windows y hacer un dual boot con linux (no aconsejable).
-  desinstalar windows e instalar linux junto con una maquina virtual de windows (ahi se permite todo, desde originales hasta modificados)

en el caso de que elijas la opcion sensata (la ultima), recuerda que debes de montar vmware o virtualbox en linux (instala linux en el ordenador
logicamente) y la maquina virtual con el windows a elegir (que ahi si puedes instalar windows antiguos) de manera oficial hasta junio de 2027, posteriormente
no va a funcionar y solo vas a poder instalar y actualizar este tipo de PCs por metodos no oficiales.

en el caso de que hayas perdido tu empleo o el curso al haberle dicho este inconveniente, mucha suerte en tu busqueda de empleo o en la busqueda de curso
(que espero que lo encuentres), con todas estas pistas que te digo ya veras como seguro al final encuentras el empleo o curso soñado.