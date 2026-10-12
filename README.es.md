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
