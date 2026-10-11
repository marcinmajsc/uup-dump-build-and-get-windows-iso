# Acerca de

Este script crea un archivo ISO con la última versión de Windows disponible desde la [Plataforma Unificada de Actualizaciones (UUP)](https://docs.microsoft.com/en-us/windows/deployment/update/windows-update-overview).

Este script encapsula el proyecto [UUP dump](https://git.uupdump.net/uup-dump) en un solo comando.

# Todo fue escrito para su uso con Github Actions.
Solo bifurca este repositorio y usa Github Actions para crear tu propia versión.

Una vez finalizados los GitHub actions, recibirás una imagen ISO terminada en dos sabores.

1. Lanzamiento con el archivo .ISO dividido en varias partes (ya que Github no permite archivos mayores a 2GB incluirlos en un lanzamiento).
Además, para cada lanzamiento, se crean paquetes para diversos sistemas y arquitecturas, que contienen un script listo para descargar todas las partes del ISO dividido y devolver el archivo ISO final.
2. Artifactos - un archivo zip único, pero es necesario iniciar sesión en el sitio web para descargar.

# También se puede ejecutar directamente en un host Windows x64, arm64 o x86 (mínimo PowerShell 5.1 / compatible con Windows 7).

## Esto es compatible con lo siguiente: 

Compilaciones de Windows:
* `windows-10`: Windows 10 19045 (aka 22H2)
* `windows-10-x86`: Windows 10 de 32 bits (x86) 19045 (aka 22H2)
* `windows-11old`: Windows 11 22631 (aka 23H2)
* `windows-11`: Windows 11 26100 (aka 24H2)
* `windows-11new`: Windows 11 26200 (aka 25H2)
* `windows-11beta`: Windows 11 26120 (aka 24H2 BETA)
* `windows-11dev`: Windows 11 26220 (aka 25H2 BETA)
* `windows-1126h1`: Windows 11 28000 (aka 26H1) <details><summary>Details</summary>para dispositivos nuevos de 2026 con silicio selecto nuevo (p. ej., Snapdragon X2) para habilitar innovaciones de hardware nuevas - no para PCs existentes o despliegues empresariales generales.</details>

* `windows-1126h2`: Windows 11 26300 (aka 26H2)
* `windows-1126h2beta`: Windows 11 26340 (aka 26H2 Experimental)
* `windows-dev`: Windows 11 26300 (aka DEV)
* `windows-canary`: Windows 11 Vista previa de Insider (aka CANARY)


Arquitectura:
* `x64`
* `arm64`
* `x86` (32-bit)


Edición:
* `home`
* `pro`
* `multi`: Home + Pro


Idioma:
* `ar-sa`: Árabe (Arabia Saudí)
* `bg-bg`: Búlgaro (Bulgaria)
* `cs-cz`: Checo (República Checa)
* `da-dk`: Danés (Dinamarca)
* `de-de`: Alemán (Alemania)
* `el-gr`: Griego (Grecia)
* `en-gb`: Inglés (Reino Unido)
* `en-us`: Inglés (Estados Unidos)
* `es-es`: Español (España)
* `es-mx`: Español (México)
* `et-ee`: Estonio (Estonia)
* `fi-fi`: Finlandés (Finlandia)
* `fr-ca`: Francés (Canadá)
* `fr-fr`: Francés (Francia)
* `he-il`: Hebreo (Israel)
* `hr-hr`: Húngaro (Croacia)
* `hu-hu`: Húngaro (Hungría)
* `it-it`: Italiano (Italia)
* `ja-jp`: Japonés (Japón)
* `ko-kr`: Coreano (Corea)
* `lt-lt`: Lituano (Lituania)
* `lv-lv`: Letón (Letonia)
* `nb-no`: Noruego Bokmål (Noruega)
* `nl-nl`: Holandés (Países Bajos)
* `pl-pl`: Polaco (Polonia)
* `pt-br`: Portugués (Brasil)
* `pt-pt`: Portugués (Portugal)
* `ro-ro`: Rumano (Rumanía)
* `ru-ru`: Ruso (Rusia)
* `sk-sk`: Eslovaco (Eslovaquia)
* `sl-si`: Esloveno (Eslovenia)
* `sr-latn-rs`: Serbio (Latín, Serbia)
* `sv-se`: Sueco (Suecia)
* `th-th`: Tailandés (Tailandia)
* `tr-tr`: Turco (Turquía)
* `uk-ua`: Ucraniano (Ucrania)
* `zh-cn`: Chino (Simplificado, China)
* `zh-tw`: Chino (Tradicional, Taiwan)


Opciones adicionales:
* `esd`: Usar compresión ESD
* `drivers`: Agregar drivers de la carpeta Drivers (compatible con x64 y x86, no arm64)
* `netfx3`: Agregar .NET Framework 3.5
* `revision`: Número de revisión del sistema


## Compatibilidad con Linux

Este script se puede ejecutar en PowerShell 7+ en Linux (mediante pwsh). Tenga en cuenta las siguientes limitaciones y consideraciones:

- El montaje de ISO usa extracción de 7-Zip en lugar de DISM (ya que los cmdlets de DISM son específicos de Windows)
- El seguimiento de progreso se adapta a diferentes formatos de registro
- Las banderas de aria2 se aplican usando un respaldo de PowerShell cuando `sed` no está disponible
- Chocolatey no es necesario; el script detecta y usa administradores de paquetes del sistema o aria2 integrado
- Algunas características específicas de Windows 11 pueden tener funcionalidad reducida en Linux

## Compatibilidad con Windows 7 / PowerShell 5.1

- Requiere PowerShell 5.1 o PowerShell 7+
- `Get-FileHash` usa el algoritmo SHA256 compatible con ambas versiones
- La salida JSON usa configuraciones de profundidad compatibles
- La extracción de ISO se adapta según las herramientas disponibles (preferencia para 7-Zip)
- Algunas funciones avanzadas de seguimiento de progreso pueden estar limitadas

### Uso

Obtener la última ISO de Windows 11 25H2:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-11new c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3
```

Cuando todo funcione correctamente, tendrás el ISO en el directorio `output`, ej. `c:/output/26200.7899.250826-1428.25H2_GE_RELEASE_SVC_PROD3_CLIENTPRO_OEMRET_X64FRE_PL-PL.ISO`.

También puedes descargar la revisión del sistema de tu elección. Por ejemplo, si quieres compilar ISO de 25H2 26200.7705:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-11new c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3 -revision 7705
```

Obtener una ISO de Windows 10 de 32 bits:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us
```

Obtener la última ISO de Windows 10 de 32 bits con todas las opciones:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us -esd -drivers -netfx3
```