# About

This creates an iso file with the latest Windows available from the [Unified Update Platform (UUP)](https://docs.microsoft.com/en-us/windows/deployment/update/windows-update-overview).

This shrink wraps the [UUP dump](https://git.uupdump.net/uup-dump) project into a single command.

# The whole was written for the use with Github Actions.
Just fork this repository and use Github Actions to build your own version.

Once the GitHub actions are complete, you'll receive a finished ISO image in two flavors.

1. Release with the .iso file split into several parts (as GitHub doesn't allow files larger than 2GB to be included in a release).
Additionally, for each release, packages are created for various systems and architectures, containing a ready-made script that downloads all parts of the split ISO and returns the finished ISO file.
2. Artifacts - a single zip file, but logging in to the website is required to download.

# You can also executed directly on a Windows x64, arm64, or x86 host (min. PowerShell 5.1 / Windows 7 compatible).

## This supports the following: 

Windows Builds:
* `windows-10`: Windows 10 19045 (aka 22H2)
* `windows-10-x86`: Windows 10 32-bit (x86) 19045 (aka 22H2)
* `windows-11old`: Windows 11 22631 (aka 23H2)
* `windows-11`: Windows 11 26100 (aka 24H2)
* `windows-11new`: Windows 11 26200 (aka 25H2)
* `windows-11beta`: Windows 11 26120 (aka 24H2 BETA)
* `windows-11dev`: Windows 11 26220 (aka 25H2 BETA)
* `windows-1126h1`: Windows 11 28000 (aka 26H1) <details><summary>Details</summary>for new 2026 devices with select new silicon (e.g., Snapdragon X2) to enable new hardware innovations - not for existing PCs or general enterprise deployments.</details>

* `windows-1126h2`: Windows 11 26300 (aka 26H2)
* `windows-1126h2beta`: Windows 11 26340 (aka 26H2 Experimental)
* `windows-dev`: Windows 11 26300 (aka DEV)
* `windows-canary`: Windows 11 Insider Preview (aka CANARY)


Architecture:
* `x64`
* `arm64`
* `x86` (32-bit)


Edition:
* `home`
* `pro`
* `multi`: Home + Pro


Language:
* `ar-sa`: Arabic (Saudi Arabia)
* `bg-bg`: Bulgarian (Bulgaria)
* `cs-cz`: Czech (Czech Republic)
* `da-dk`: Danish (Denmark)
* `de-de`: German (Germany)
* `el-gr`: Greek (Greece)
* `en-gb`: English (United Kingdom)
* `en-us`: English (United States)
* `es-es`: Spanish (Spain)
* `es-mx`: Spanish (Mexico)
* `et-ee`: Estonian (Estonia)
* `fi-fi`: Finnish (Finland)
* `fr-ca`: French (Canada)
* `fr-fr`: French (France)
* `he-il`: Hebrew (Israel)
* `hr-hr`: Croatian (Croatia)
* `hu-hu`: Hungarian (Hungary)
* `it-it`: Italian (Italy)
* `ja-jp`: Japanese (Japan)
* `ko-kr`: Korean (Korea)
* `lt-lt`: Lithuanian (Lithuania)
* `lv-lv`: Latvian (Latvia)
* `nb-no`: Norwegian Bokmål (Norway)
* `nl-nl`: Dutch (Netherlands)
* `pl-pl`: Polish (Poland)
* `pt-br`: Portuguese (Brazil)
* `pt-pt`: Portuguese (Portugal)
* `ro-ro`: Romanian (Romania)
* `ru-ru`: Russian (Russia)
* `sk-sk`: Slovak (Slovakia)
* `sl-si`: Slovenian (Slovenia)
* `sr-latn-rs`: Serbian (Latin, Serbia)
* `sv-se`: Swedish (Sweden)
* `th-th`: Thai (Thailand)
* `tr-tr`: Turkish (Turkey)
* `uk-ua`: Ukrainian (Ukraine)
* `zh-cn`: Chinese (Simplified, China)
* `zh-tw`: Chinese (Traditional, Taiwan)


Additional options:
* `esd`: Use ESD compression
* `drivers`: Add drivers from Drivers folder (compatible with x64 and x86, not arm64)
* `netfx3`: Add .NET Framework 3.5
* `revision`: System Revision Number


## Linux Compatibility

This script can be run on PowerShell 7+ on Linux (via pwsh). Note the following limitations and considerations:

- ISO mounting uses 7-Zip extraction instead of DISM (since DISM cmdlets are Windows-specific)
- Progress tracking adapts to different log formats
- aria2 flags are patched using PowerShell fallback when `sed` is not available
- Chocolatey is not required; the script detects and uses system package managers or bundled aria2
- Some Windows 11 specific features may have reduced functionality on Linux

## Windows 7 / PowerShell 5.1 Compatibility

- Requires PowerShell 5.1 or PowerShell 7+
- `Get-FileHash` uses SHA256 algorithm compatible with both versions
- JSON output uses compatible depth settings
- ISO extraction adapts based on available tools (7-Zip preferred)
- Some advanced progress tracking features may be limited

### Usage

Get the latest Windows 11 25H2 iso:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-11new c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3
```

When everything works correctly, you'll have the iso in the `output` directory at, e.g., `c:/output/26200.7899.250826-1428.25H2_GE_RELEASE_SVC_PROD3_CLIENTPRO_OEMRET_X64FRE_PL-PL.ISO`.

You can also download the system revision of your choice. For example, if you want to build 25H2 26200.7705 iso:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-11new c:/output -architecture x64 -edition pro -lang en-us -esd -drivers -netfx3 -revision 7705
```

Get a 32-bit Windows 10 ISO:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us
```

Get the latest 32-bit Windows 10 ISO with all options:

```bash
powershell uup-dump-get-windows-iso.ps1 windows-10-x86 c:/output -architecture x86 -edition pro -lang en-us -esd -drivers -netfx3
```

ATTENTION, NOTICE (October 12, 2026): microsoft will cut off starting June 19,
2027 the access to windows update for all the computers that have windows 10
without ESU and below (the previous block was up to windows vista-server 2008
without R2), this logically affects the server versions (server 2008 R2 up to
server 2019, from server 2022 onwards, the windows update closure doesn't
affect it), this is due to the expiry of the root certificates of the update
service that expire as of this date, if you want to take a look at the official
link of the microsoft news, here it is (use the browser translation, it's in
English):

https://techcommunity.microsoft.com/blog/windows-itpro-blog/prepare-for-windows-update-certificate-rotation-in-2027/4562463

remember that root certificates are part of internet browsing, one of the
characteristics of the https protocol is that now everything that is transferred
to the router is encrypted (previously it wasn't so), but for programs used to
analyze everything that is transferred on a home network like wireshark to have
no effect (no sensitive data is seen), the root certificates must work and be
up to date, if they don't work, it gives a certificate error in the browser and
the programs that connect to the internet will stop working, you have to take
this into account when using an old windows installed on the computer (by the
way, the windows update closure also affects virtual machines, i.e., the PCs
booted inside a physical machine).

when the expiry date of the root certificate arrives it's possible that the
offices installed on windows without support give errors checking updates (up
to 10 and server 2019 which are client and server respectively you can install
the 2021-365, 7 and 8, up to office 2016), this being solved by deactivating
the office updates (when the expiry date of said root certificates arrives).

in the previous window (automatic updates were imposed starting from windows
2000) it didn't give any kind of failure when booting the operating system,
only when opening the microsoft update page or starting the windows update.
(I experienced the previous update closure window).

in case it's windows 10 with ESU, windows 11 24H2, LTSC servers of 2019 and
2016 and server 2022, microsoft has put as the official method to solve the
problem, the update, i.e., you'll have to update the second Tuesday of each
month until the date of June 19, 2027 in which already...piano, piano (you'll
understand what I'm telling you).

in case you come across this type of computers, these are the paths you have:

-  buy the ESU (windows 10) (in the case of countries of the european union, it has no cost)
-  patch the update to access the ESU, the only patch (and recommended for windows 10) is the MAS (microsoft activation script)
-  install an unofficial patch to update the root certificates, which is the legacy update
-  in the case of compatible versions (it's not mandatory for now from 11 24H2, windows 10 without ESU is essential
half-way) accept the updates to major versions of windows via update or doing an update from the windows installation
media.
-  keep the windows installation and do a dual boot with linux (not advisable).
-  uninstall windows and install linux together with a windows virtual machine (there everything is allowed, from originals to modified ones)

in case you choose the sensible option (the last one), remember that you must
set up vmware or virtualbox on linux (install linux on the computer logically)
and the virtual machine with the windows of your choice (that there you can
indeed install old windows) in an official way until June 2027, afterwards it
won't work and you'll only be able to install and update this type of PCs by
unofficial methods.

in case you've lost your job or the course for having told you this
inconvenience, good luck in your job search or in the course search (which I
hope you find), with all these clues I tell you you'll see how surely in the
end you find the dreamed job or course.
