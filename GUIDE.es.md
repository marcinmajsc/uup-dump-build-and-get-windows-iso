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