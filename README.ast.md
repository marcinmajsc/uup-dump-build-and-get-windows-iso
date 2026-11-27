# Acerca de

Esti script crea un ficheru ISO cola última versión de Windows disponible dende la [Plataforma Unificada d'Actualizaciones (UUP)](https://docs.microsoft.com/en-us/windows/deployment/update/windows-update-overview).

Esti script empaqueta'l proyeutu [UUP dump](https://git.uupdump.net/uup-dump) nun solu comandu.

# Too foi escritu pa usalo con Github Actions.
Namás faes un fork d'esti repositoriu y usas Github Actions pa crear la to propia versión.

Una vez terminaos los GitHub actions, vas recibir una imaxe ISO terminada en dos variantes.

1. Lanzamientu col ficheru .ISO estremáu en varies partes (yá que GitHub nun dexa incluyir ficheros de más de 2GB nun lanzamientu).
Amás, pa cada lanzamientu, créense paquetes pa distintos sistemes y arquitectures, que contienen un script listu pa baxar toles partes de la ISO estremada y devolver el ficheru ISO final.
2. Artifactos - un ficheru zip únicu, pero ye necesariu entrar na páxina web pa baxalo.

# Tamién se pue executar direutamente nun equipu Windows x64, arm64 o x86 (mínimu PowerShell 5.1 / compatible con Windows 7).

## Esto ye compatible con lo siguiente: 

Compilaciones de Windows:
* `windows-10`: Windows 10 19045 (aka 22H2)
* `windows-10-x86`: Windows 10 de 32 bits (x86) 19045 (aka 22H2)
* `windows-11old`: Windows 11 22631 (aka 23H2)
* `windows-11`: Windows 11 26100 (aka 24H2)
* `windows-11new`: Windows 11 26200 (aka 25H2)
* `windows-11beta`: Windows 11 26120 (aka 24H2 BETA)
* `windows-11dev`: Windows 11 26220 (aka 25H2 BETA)
* `windows-1126h1`: Windows 11 28000 (aka 26H1) <details><summary>Details</summary>pa dispositivos nuevos de 2026 con siliciu selecto nuevo (p. ex., Snapdragon X2) pa habilitar innovaciones de hardware nueves - non pa PCs esistentes nin despliegues empresariales xenerales.</details>

* `windows-1126h2`: Windows 11 26300 (aka 26H2)
* `windows-1126h2beta`: Windows 11 26340 (aka 26H2 Experimental)
* `windows-dev`: Windows 11 26300 (aka DEV)
* `windows-canary`: Windows 11 Vista previa d'Insider (aka CANARY)


Arquiteutura:
* `x64`
* `arm64`
* `x86` (32 bits)


Edición:
* `home`
* `pro`
* `multi`: Home + Pro


Llingua:
* `ar-sa`: Árabe (Arabia Saudí)
* `bg-bg`: Búlgaru (Bulgaria)
* `cs-cz`: Checu (República Checa)
* `da-dk`: Danés (Dinamarca)
* `de-de`: Alemán (Alemania)
* `el-gr`: Griegu (Grecia)
* `en-gb`: Inglés (Reinu Xuníu)
* `en-us`: Inglés (Estaos Xuníos)
* `es-es`: Español (España)
* `es-mx`: Español (Méxicu)
* `et-ee`: Estoniu (Estonia)
* `fi-fi`: Finlandés (Finlandia)
* `fr-ca`: Francés (Canadá)
* `fr-fr`: Francés (Francia)
* `he-il`: Hebréu (Israel)
* `hr-hr`: Croata (Croacia)
* `hu-hu`: Húngaru (Hungría)
* `it-it`: Italianu (Italia)
* `ja-jp`: Xaponés (Xapón)
* `ko-kr`: Coreanu (Corea)
* `lt-lt`: Lituano (Lituania)
* `lv-lv`: Letón (Letonia)
* `nb-no`: Noruegu Bokmål (Noruega)
* `nl-nl`: Holandés (Países Baxos)
* `pl-pl`: Polacu (Polonia)
* `pt-br`: Portugués (Brasil)
* `pt-pt`: Portugués (Portugal)
* `ro-ro`: Rumanu (Rumanía)
* `ru-ru`: Rusu (Rusia)
* `sk-sk`: Eslovacu (Eslovaquia)
* `sl-si`: Eslovenu (Eslovenia)
* `sr-latn-rs`: Serbiu (Llatín, Serbia)
* `sv-se`: Suecu (Suecia)
* `th-th`: Tailandés (Tailandia)
* `tr-tr`: Turcu (Turquía)
* `uk-ua`: Ucraín (Ucrania)
* `zh-cn`: Chinu (Simplificáu, China)
* `zh-tw`: Chinu (Tradicional, Taiwán)


Opciones adicionales:
* `esd`: Usar compresión ESD
* `drivers`: Amestar controladores de la carpeta Drivers (compatible con x64 y x86, non arm64)
* `netfx3`: Amestar .NET Framework 3.5
* `revision`: Númberu de revisión del sistema


## Compatibilidad con Linux

Esti script pue executase en PowerShell 7+ en Linux (per mediación de pwsh). Ten en cuenta les siguientes llimitaciones y consideraciones:

- El montaxe de ISO usa estraición con 7-Zip en llugar de DISM (yá que los cmdlets de DISM son específicos de Windows)
- El siguir el progresu afítese a distintos formatos de rexistru
- Les banderes d'aria2 aplíquense usando una alternativa de PowerShell cuando `sed` nun ta disponible
- Chocolatey nun fai falta; el script detecta y usa los xestores de paquetes del sistema o l'aria2 incluyíu
- Delles carauterístiques específiques de Windows 11 pueden tener menos funcionalidá en Linux

## Compatibilidad con Windows 7 / PowerShell 5.1

- Requiere PowerShell 5.1 o PowerShell 7+
- `Get-FileHash` usa l'algoritmu SHA256 compatible con dambes versiones
- La salida JSON usa axustes de fondu compatibles
- La estraición de ISO afítese a les ferramientes disponibles (prefierse 7-Zip)
- Dellos siguidores de progresu avanzaos pueden tar llindaos

### Usu

Llograr la última ISO de Windows 11 26H2:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-1126h2 c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3
```

Cuando too funcione correutamente, vas tener la ISO nel directoriu `output`, p. ex. `c:/output/26300.9711.261009-2244.26H2_GE_RELEASE_SVC_PROD1_CLIENTPRO_OEMRET_X64FRE_EN-US.l.ISO`.

Tamién puedes baxar la revisión del sistema que escojas. Por exemplu, si quies compilar la ISO de 25H2 26200.7705:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-11new c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3 -revision 7705
```

Llograr una ISO de Windows 10 de 32 bits:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us
```

Llograr la última ISO de Windows 10 de 32 bits con toles opciones:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us -esd -drivers -netfx3
```

ATENCIÓN, AVISO (12 d'ochobre de 2026): microsoft va cortar a partir
del 19 de xunu de 2027 l'accesu a windows update a tolos equipos que
tengan windows 10 ensin ESU y anteriores (el bloqueu anterior foi hasta
windows vista-server 2008 ensin R2), esto lóxicamente afecta a les versiones
de servidor (server 2008 R2 hasta server 2019, dende server 2022 d'equí
p'arriba, el zarru de windows update nun los afecta), esto ye por mor de la
caducidá de los certificaos raíz del serviciu d'actualizaciones que
caduquen a partir d'esta fecha, si quies echar un vistazu al enllaz oficial
de la noticia de microsoft, equí te lo dexo (usa la traducción del navegador, ta n'inglés):

https://techcommunity.microsoft.com/blog/windows-itpro-blog/prepare-for-windows-update-certificate-rotation-in-2027/4562463

recuerda que los certificaos raíz formen parte de la navegación per internet, una de les
carauterístiques del protocolu https ye que agora too lo que se tresfier al router
va cifráu (enantes nun yera asina), pero pa que programes usaos pa analizar too lo que se
transfier nuna rede doméstica como wireshark nun surtan nengún efeutu (nun se vea nengún
dato sensible), los certificaos raíz tienen de funcionar y tar al día, si nun funcionen,
da error de certificáu nel navegador y los programes que conecten a internet van dexar
de funcionar, esto has de tenerlo en cuenta a la hora d'usar un windows antiguu instaláu
nel ordenador (per ciertu, el zarru de windows update tamién afecta a les máquines
virtuales, o seya, a los PCs arrancaos dentro d'un equipu físicu).

cuando llegue la fecha de caducidá del certificáu raíz ye posible que nos offices
instalaos en windows ensin soporte den errores de comprobación d'actualizaciones (hasta
10 y server 2019 que son veceru y servidor respeutivamente pue instalase el 2021-365,
7 y 8, hasta office 2016), soluciónase esto desactivando les actualizaciones d'office
(cuando llegue la fecha de caducidá de dichos certificaos raíz).

na ventana anterior (les actualizaciones automátiques impunxéronse a partir de windows
2000) nun dio nengún tipu de fallu a la hora d'arrancar el sistema operativu, namás
a la hora d'abrir la páxina de microsoft update o d'empezar el windows update.
(pasi la esperiencia de la ventana anterior de zarru del update).

no casu de que seya windows 10 con ESU, windows 11 24H2, servidores LTSC de 2019 y
2016 y server 2022, microsoft punxo como métodu oficial pa solucionar el problema
la actualización, o seya, vas tener d'actualizar el segundu martes de cada mes
hasta la fecha del 19 de xunu de 2027 na que yá...piano, piano (vas entender lo que te digo).

no casu de que te topes con esti tipu d'equipos, estos son los caminos que tienes:

-  mercar el ESU (windows 10) (no casu de países de la unión europea, nun tien nengún coste)
-  parchear el update p'acceder al ESU, que l'únicu parche (y recomendable pa windows 10) ye'l MAS (microsoft activation script)
-  instalar un parche non oficial p'actualizar los certificaos raíz, que ye'l legacy update
-  no casu de versiones compatibles (nun ye obligatoriu de momentu dende 11 24H2, windows 10 ensin ESU ye imprescindible
a medies) aceptar les actualizaciones a versiones mayores de windows per update o faciendo una actualización dende los
medios d'instalación de windows.
-  caltener la instalación de windows y facer un dual boot con linux (non aconseyable).
-  desinstalar windows ya instalar linux xunto con una máquina virtual de windows (equí tán permitees toles opciones, dende orixinales hasta modificaes)

no casu de que escojas la opción sensata (la postrera), recuerda que has de montar vmware o virtualbox en linux (instala linux nel ordenador
lóxicamente) y la máquina virtual col windows que escojas (equí sí puedes instalar windows antiguos) de manera oficial hasta xunu de 2027, darréu
nun va funcionar y namás vas poder instalar y actualizar esti tipu de PCs per métodos non oficiales.

no casu de que perdieres el puestu de trabayu o el cursu por dicirte esti inconveniente, muncha suerte na to busca d'empleu o na busca de cursu
(que espero que lo atopes), con toles pistes que te digo yá vas ver como de xuru al final atopes l'empleu o el cursu que sueñes.
