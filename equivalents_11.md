================================================================================
WINDOWS 11 BETA VERSION NAMING COMPARISON
================================================================================

This file maps how Windows 11 beta versions are named in UUPdump versus
how Microsoft names them.

================================================================================
SECTION 1: UUPdump BETA VERSION NAMES (List Mode)
================================================================================

The following Windows 11 beta/preview targets are supported in the script:

1. windows-11beta
   - UUPdump name: windows-11beta
   - Build: 26120 (24H2 Beta)
   - Ring: Beta
   - Microsoft channel: 24H2 Beta

2. windows-11dev
   - UUPdump name: windows-11dev
   - Build: 26220 (Dev Channel)
   - Ring: Wif (Windows Insider Federation)
   - Microsoft channel: Dev Channel

3. windows-1126h2beta
   - UUPdump name: windows-1126h2beta
   - Build: 26340 (26H2 Experimental)
   - Ring: Not explicitly labeled (Experimental)
   - Microsoft channel: 26H2 Experimental

4. windows-canary
   - UUPdump name: windows-canary
   - Build: Latest Canary builds
   - Ring: Canary
   - Microsoft channel: Canary Channel

================================================================================
SECTION 2: MICROSOFT vs UUPdump NAMING COMPARISON TABLE
================================================================================

This table shows the equivalent naming between Microsoft's channel names
and UUPdump's target names.

+---------------------+----------------------+----------------------+------------------+
| Microsoft Name      | Microsoft Description| UUPdump Name         | UUPdump Description|
+---------------------+----------------------+----------------------+------------------+
| Beta Channel        | General beta releases| windows-11beta       | 24H2 Beta (26120)|
| Dev Channel         | Development channel  | windows-11dev        | Dev Channel (26220)|
| Canary Channel      | Fast ring preview    | windows-canary       | Canary builds    |
| 26H2 Experimental   | New hardware innovation| windows-1126h2beta | 26H2 Experimental (26340)|
| Release Preview     | Final beta before GA | (not separately mapped)| windows-11beta   |
+---------------------+----------------------+----------------------+------------------+

================================================================================
SECTION 3: DETAILED MAPPING

================================================================================
Microsoft Naming                    | UUPdump Target Name
================================================================================
"Beta Channel"                    | windows-11beta
   - Represents: 24H2 Beta releases (build 26120)
   - Used for: General beta testing of Windows 11 24H2

"Dev Channel"                     | windows-11dev
   - Represents: Windows Insider Dev Channel releases (build 26220)
   - Used for: Development preview builds

"Canary Channel"                  | windows-canary
   - Represents: Fast ring/Canary releases
   - Used for: Latest experimental features

"26H2 Experimental"               | windows-1126h2beta
   - Represents: 26H2 Experimental releases (build 26340)
   - Used for: New silicon innovations (e.g., Snapdragon X2)
   - Note: Not for existing PCs or general enterprise deployments

================================================================================
SECTION 4: ADDITIONAL CONTEXT

================================================================================

Important Notes:

1. windows-11old (22631) - This is NOT a beta, but the original
   Windows 11 23H2 stable release. It's included for comparison.

2. The script uses "ring" labels to distinguish between channels:
   - Beta: General beta testing
   - Wif: Windows Insider Federation (Dev channel)
   - Dev: Development channel
   - Canary: Fast ring/Canary

3. Microsoft's naming conventions have evolved separately from uup-dump's
   naming. This file documents the mapping between the two systems.

4. The script supports these Windows 11 targets (in order of stability):
   - windows-11old: Most stable (23H2)
   - windows-11: Latest stable (24H2)
   - windows-11new: Next release (25H2)
   - windows-11beta: Beta channel (24H2)
   - windows-11dev: Dev channel (based on 25H2)
   - windows-1126h1: New hardware (26H1)
   - windows-1126h2: Stable 26H2
   - windows-1126h2beta: Experimental 26H2
   - windows-dev: Dev channel
   - windows-canary: Canary channel

================================================================================
