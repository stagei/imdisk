# ImDisk Virtual Disk Driver - Architecture Documentation

This document explains the architecture and component interactions of the ImDisk Virtual Disk Driver codebase. It covers the C++ kernel driver, user-mode services, command-line tools, control panel applet, and .NET wrapper libraries.

## Table of Contents

- [Overview](#overview)
- [High-Level Architecture](#high-level-architecture)
- [Component Breakdown](#component-breakdown)
  - [Kernel Driver (sys/)](#kernel-driver-sys)
  - [Command-Line Interface (cli/)](#command-line-interface-cli)
  - [Proxy Service (svc/)](#proxy-service-svc)
  - [Device I/O Library (devio/)](#device-io-library-devio)
  - [Control Panel Applet (cpl/)](#control-panel-applet-cpl)
  - [AWE Allocation Driver (awealloc/)](#awe-allocation-driver-awealloc)
  - [.NET Libraries (ImDiskNet/)](#net-libraries-imdisknet)
- [Data Flow Diagrams](#data-flow-diagrams)
- [Key Data Structures](#key-data-structures)
- [IOCTL Interface](#ioctl-interface)
- [Proxy Protocol](#proxy-protocol)

---

## Overview

ImDisk is a virtual disk driver for Windows that emulates:
- **Hard disk partitions**
- **Floppy drives**
- **CD/DVD-ROM drives**

These virtual disks can be backed by:
1. **Image files** on disk
2. **Virtual memory** (RAM disk)
3. **Physical memory** via AWEAlloc driver
4. **Proxy connections** (named pipes, TCP/IP, serial ports, shared memory)

---

## High-Level Architecture

```mermaid
flowchart TB
    subgraph UserMode["User Mode"]
        CLI["imdisk.exe<br/>(Command Line)"]
        CPL["imdisk.cpl<br/>(Control Panel)"]
        NET[".NET Applications<br/>(ImDiskNet)"]
        SVC["ImDskSvc.exe<br/>(Proxy Service)"]
        DEVIO["devio.exe<br/>(I/O Server)"]
    end

    subgraph KernelMode["Kernel Mode"]
        DRV["imdisk.sys<br/>(Virtual Disk Driver)"]
        AWE["awealloc.sys<br/>(Physical Memory Driver)"]
    end

    subgraph Storage["Storage Backends"]
        FILE["Image Files"]
        VM["Virtual Memory"]
        PHYS["Physical RAM<br/>(AWE)"]
        PROXY["Remote Proxy<br/>(TCP/Pipe/COM)"]
    end

    CLI -->|IOCTL| DRV
    CPL -->|IOCTL| DRV
    NET -->|P/Invoke| CPL
    NET -->|IOCTL| DRV
    
    SVC <-->|Named Pipe| DRV
    DEVIO <-->|Proxy Protocol| SVC
    DEVIO <-->|Direct| DRV
    
    DRV -->|Read/Write| FILE
    DRV -->|Alloc/Free| VM
    DRV -->|Read/Write| AWE
    DRV <-->|I/O Requests| SVC
    AWE -->|MmAllocatePagesForMdl| PHYS
    
    SVC <-->|TCP/IP| PROXY
    SVC <-->|Serial| PROXY
```

---

## Component Breakdown

### Kernel Driver (sys/)

The core kernel-mode driver that creates and manages virtual disk devices.

```mermaid
flowchart LR
    subgraph Driver["imdisk.sys"]
        ENTRY["DriverEntry"]
        IODISP["I/O Dispatch"]
        CREATE["CreateDevice"]
        DEVTHRD["Device Thread"]
        PROXY["Proxy Client"]
        FLOPPY["Floppy Emulation"]
        COMMON["Common I/O"]
        LOWER["Lower Device I/O"]
    end

    ENTRY --> IODISP
    IODISP --> CREATE
    CREATE --> DEVTHRD
    DEVTHRD --> COMMON
    DEVTHRD --> PROXY
    DEVTHRD --> FLOPPY
    COMMON --> LOWER
```

**Key Source Files:**

| File | Purpose |
|------|---------|
| `imdisk.cpp` | Driver entry point and main initialization |
| `iodisp.cpp` | IRP dispatch handlers (Create, Close, Read, Write, DeviceControl) |
| `createdev.cpp` | Device object creation and configuration |
| `devthrd.cpp` | Worker thread for I/O processing |
| `proxy.cpp` | Proxy connection client (pipe, TCP, shared memory) |
| `floppy.cpp` | Floppy disk geometry and format emulation |
| `commonio.cpp` | Common I/O routines |
| `lowerdev.cpp` | Pass-through to underlying storage devices |
| `wkmem.cpp` | Kernel memory management utilities |
| `imdsksys.h` | Internal header with structures and prototypes |

**Device Extension Structure:**

```mermaid
classDiagram
    class DEVICE_EXTENSION {
        +ULONG device_number
        +HANDLE file_handle
        +PDEVICE_OBJECT dev_object
        +PFILE_OBJECT file_object
        +BOOLEAN parallel_io
        +PUCHAR image_buffer
        +BOOLEAN byte_swap
        +BOOLEAN shared_image
        +PROXY_CONNECTION proxy
        +UNICODE_STRING file_name
        +WCHAR drive_letter
        +DISK_GEOMETRY disk_geometry
        +LARGE_INTEGER image_offset
        +BOOLEAN read_only
        +BOOLEAN vm_disk
        +BOOLEAN awealloc_disk
        +BOOLEAN use_proxy
        +PKTHREAD device_thread
    }
    
    class PROXY_CONNECTION {
        +PROXY_CONNECTION_TYPE connection_type
        +PFILE_OBJECT device
        +HANDLE request_event_handle
        +PKEVENT request_event
        +HANDLE response_event_handle
        +PKEVENT response_event
        +PUCHAR shared_memory
        +ULONG_PTR shared_memory_size
    }
    
    DEVICE_EXTENSION --> PROXY_CONNECTION : contains
```

---

### Command-Line Interface (cli/)

User-mode command-line tool for managing virtual disks.

**Source File:** `imdisk.c`

**Capabilities:**
- `-a` : Attach (create) virtual disk
- `-d` / `-D` : Detach (remove) virtual disk
- `-l` : List virtual disks
- `-e` : Edit existing virtual disk
- `-R` : Emergency removal

```mermaid
sequenceDiagram
    participant User
    participant CLI as imdisk.exe
    participant Driver as imdisk.sys
    participant FS as File System

    User->>CLI: imdisk -a -t file -f image.img -m X:
    CLI->>CLI: Parse arguments
    CLI->>Driver: Open \\.\ImDiskCtl
    CLI->>Driver: IOCTL_IMDISK_CREATE_DEVICE
    Driver->>Driver: Create device thread
    Driver->>Driver: Open image file
    Driver->>Driver: Create device object
    Driver-->>CLI: Return device number
    CLI->>FS: Create mount point X:
    CLI-->>User: Success
```

---

### Proxy Service (svc/)

Windows service that forwards I/O requests to remote storage.

**Source File:** `imdsksvc.cpp`

**Functions:**
- Accepts connections from kernel driver via named pipe
- Forwards I/O to TCP/IP hosts, serial ports, or other endpoints
- Runs as Windows service (ImDskSvc)

```mermaid
sequenceDiagram
    participant Driver as imdisk.sys
    participant Pipe as Named Pipe
    participant Service as ImDskSvc
    participant Remote as Remote Server

    Driver->>Pipe: IMDPROXY_REQ_CONNECT
    Pipe->>Service: Receive connect request
    Service->>Remote: Open TCP connection
    Remote-->>Service: Connected
    Service-->>Pipe: IMDPROXY_CONNECT_RESP
    Pipe-->>Driver: Connection established

    loop I/O Operations
        Driver->>Pipe: IMDPROXY_REQ_READ/WRITE
        Pipe->>Service: Forward request
        Service->>Remote: Send request
        Remote-->>Service: Return data
        Service-->>Pipe: IMDPROXY_READ/WRITE_RESP
        Pipe-->>Driver: I/O complete
    end
```

---

### Device I/O Library (devio/)

Cross-platform library for storage server implementations.

**Key Files:**

| File | Purpose |
|------|---------|
| `devio.c` | Core device I/O routines |
| `devio.h` | Public API header |
| `devio_types.h` | Type definitions |
| `safeio.c` | Safe I/O wrappers |
| `win32_fileio.cpp` | Windows file I/O implementation |
| `iobridge/` | Bridge for connecting devio to other systems |

---

### Control Panel Applet (cpl/)

Windows Control Panel interface for managing virtual disks.

**Key Files:**

| File | Purpose |
|------|---------|
| `imdisk.cpp` | Control Panel applet entry and dialogs |
| `drvio.c` | Driver I/O helper functions |
| `mbr.c` | MBR partition table handling |
| `rundll.c` | RunDLL32 compatible entry points |
| `wconmsg.cpp` | Console message output |

The CPL exports a DLL (`imdisk.cpl`) that can be called via:
- Control Panel integration
- `rundll32.exe imdisk.cpl,RunDLL_MountFile filename`

---

### AWE Allocation Driver (awealloc/)

Kernel driver for allocating physical RAM pages for high-performance RAM disks.

**Source File:** `awealloc.c`

```mermaid
flowchart TB
    subgraph AWEAlloc["awealloc.sys"]
        ALLOC["Allocate Pages"]
        MAP["Map to Virtual"]
        IO["Read/Write"]
        FREE["Free Pages"]
    end

    subgraph Physical["Physical Memory"]
        PAGES["RAM Pages"]
    end

    subgraph ImDisk["imdisk.sys"]
        VDISK["Virtual Disk"]
    end

    ImDisk -->|Open AWEAlloc| AWEAlloc
    ALLOC -->|MmAllocatePagesForMdl| PAGES
    MAP -->|MmMapLockedPagesSpecifyCache| PAGES
    IO --> MAP
    VDISK -->|Read/Write| IO
    FREE -->|MmFreePagesFromMdl| PAGES
```

**Key Structures:**

```c
typedef struct _BLOCK_DESCRIPTOR {
    LONGLONG Offset;
    PMDL Mdl;
    struct _BLOCK_DESCRIPTOR *NextBlock;
} BLOCK_DESCRIPTOR;

typedef struct _PAGE_CONTEXT {
    LONGLONG UsageCount;
    LONGLONG PageBase;
    PMDL Mdl;
    PUCHAR Ptr;
} PAGE_CONTEXT;
```

---

### .NET Libraries (ImDiskNet/)

Managed wrappers for the ImDisk API.

```mermaid
flowchart TB
    subgraph Solution["ImDiskNet.sln"]
        IMDISKNET["ImDiskNet.dll<br/>(Core Library)"]
        DEVIONET["DevioNet.dll<br/>(Server Library)"]
        DISCUTILS["DiscUtilsDevio.exe<br/>(DiscUtils Server)"]
    end

    subgraph ImDiskNetLib["ImDiskNet"]
        API["ImDiskAPI"]
        DEVICE["ImDiskDevice"]
        STREAM["ImDiskDeviceStream"]
        CONTROL["ImDiskControl"]
        FLAGS["Flags & Enums"]
    end

    subgraph DevioNetLib["DevioNet"]
        subgraph Providers["Providers"]
            PFILE["DevioProviderFromStream"]
            PMEM["DevioProviderFromMemory"]
            PDISK["DevioProviderFromDisk"]
            PLIB["DevioProviderFromLib"]
        end
        subgraph Services["Services"]
            SSHM["DevioShmService"]
            STCP["DevioTcpService"]
            SNET["DevioNoneService"]
            SDRV["DevioServiceBase"]
        end
        subgraph Clients["Clients"]
            CSHM["DevioShmStream"]
            CTCP["DevioTcpStream"]
            CSTR["DevioStream"]
        end
    end

    IMDISKNET --> ImDiskNetLib
    DEVIONET --> DevioNetLib
    DISCUTILS --> DEVIONET
    
    API -->|P/Invoke| CPL2["imdisk.cpl"]
    DEVICE -->|IOCTL| DRV2["imdisk.sys"]
```

**ImDiskAPI Class Methods:**

```vb
Public Class ImDiskAPI
    ' Create virtual disk
    Public Shared Function CreateDevice(
        DiskSize As Long,
        TracksPerCylinder As UInt32,
        SectorsPerTrack As UInt32,
        BytesPerSector As UInt32,
        ImageOffset As Long,
        Flags As ImDiskFlags,
        FileName As String,
        NativePath As Boolean,
        MountPoint As String) As UInt32

    ' Remove virtual disk
    Public Shared Sub RemoveDevice(DeviceNumber As UInt32)
    
    ' Query device info
    Public Shared Function QueryDevice(DeviceNumber As UInt32) As ImDiskDevice
    
    ' Get list of devices
    Public Shared Function GetDeviceList() As UInt32()
    
    ' Events
    Public Shared Event DriveListChanged As EventHandler
End Class
```

---

## Data Flow Diagrams

### Virtual Disk Creation Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant CPL as imdisk.cpl
    participant CTL as ImDiskCtl Device
    participant DRV as imdisk.sys
    participant THR as Device Thread
    participant STOR as Storage Backend

    App->>CPL: ImDiskCreateDevice()
    CPL->>CTL: Open \\.\ImDiskCtl
    CPL->>CTL: IOCTL_IMDISK_CREATE_DEVICE
    CTL->>DRV: Process IOCTL
    DRV->>DRV: Validate parameters
    DRV->>DRV: Find free device number
    DRV->>THR: Create device thread
    THR->>THR: Impersonate caller
    THR->>STOR: Open storage (file/proxy)
    THR->>DRV: Create \Device\ImDiskN
    DRV->>DRV: Create symbolic link
    DRV-->>CTL: Return success
    CTL-->>CPL: Device created
    CPL->>App: Assign mount point
    CPL-->>App: Return device number
```

### I/O Request Flow (File-Backed)

```mermaid
sequenceDiagram
    participant FS as File System
    participant DRV as imdisk.sys
    participant THR as Device Thread
    participant FILE as Image File

    FS->>DRV: IRP_MJ_READ/WRITE
    DRV->>DRV: Validate request
    DRV->>THR: Queue IRP
    THR->>THR: Dequeue IRP
    THR->>FILE: ZwReadFile/ZwWriteFile
    FILE-->>THR: Data/Status
    THR->>THR: Apply byte-swap if needed
    THR->>DRV: Complete IRP
    DRV-->>FS: Return data/status
```

### Proxy I/O Flow

```mermaid
sequenceDiagram
    participant FS as File System
    participant DRV as imdisk.sys
    participant THR as Device Thread
    participant PROXY as Proxy Connection
    participant SVC as ImDskSvc
    participant REMOTE as Remote Storage

    FS->>DRV: IRP_MJ_READ
    DRV->>THR: Queue IRP
    THR->>PROXY: ImDiskReadProxy()
    PROXY->>SVC: IMDPROXY_REQ_READ
    SVC->>REMOTE: Forward read request
    REMOTE-->>SVC: Return data
    SVC-->>PROXY: IMDPROXY_READ_RESP + data
    PROXY-->>THR: Data received
    THR->>DRV: Complete IRP
    DRV-->>FS: Return data
```

---

## Key Data Structures

### IMDISK_CREATE_DATA

Used for creating and querying virtual disks:

```c
typedef struct _IMDISK_CREATE_DATA {
    ULONG           DeviceNumber;      // Device number (input/output)
    DISK_GEOMETRY   DiskGeometry;      // Virtual geometry (Cylinders = total size)
    LARGE_INTEGER   ImageOffset;       // Offset in image file
    ULONG           Flags;             // Type and option flags
    WCHAR           DriveLetter;       // Drive letter (if used)
    USHORT          FileNameLength;    // Length of FileName
    WCHAR           FileName[1];       // Variable-length filename
} IMDISK_CREATE_DATA;
```

### Device Type Flags

```mermaid
graph LR
    subgraph DeviceType["IMDISK_DEVICE_TYPE_xxx"]
        HD["HD (0x10)<br/>Hard Disk"]
        FD["FD (0x20)<br/>Floppy"]
        CD["CD (0x30)<br/>CD-ROM"]
        RAW["RAW (0x40)<br/>Raw Device"]
    end
    
    subgraph BackingType["IMDISK_TYPE_xxx"]
        FILE["FILE (0x100)<br/>Image File"]
        VM["VM (0x200)<br/>Virtual Memory"]
        PROXY["PROXY (0x300)<br/>Proxy Service"]
    end
    
    subgraph ProxyType["IMDISK_PROXY_TYPE_xxx"]
        DIRECT["DIRECT (0x0000)"]
        COMM["COMM (0x1000)<br/>Serial Port"]
        TCP["TCP (0x2000)<br/>TCP/IP"]
        SHM["SHM (0x3000)<br/>Shared Memory"]
    end
    
    subgraph FileType["IMDISK_FILE_TYPE_xxx"]
        QUEUED["QUEUED_IO (0x0000)"]
        AWE["AWEALLOC (0x1000)"]
        PARALLEL["PARALLEL_IO (0x2000)"]
        BUFFERED["BUFFERED_IO (0x3000)"]
    end
```

---

## IOCTL Interface

| IOCTL Code | Description |
|------------|-------------|
| `IOCTL_IMDISK_QUERY_VERSION` | Query driver version |
| `IOCTL_IMDISK_CREATE_DEVICE` | Create new virtual disk |
| `IOCTL_IMDISK_QUERY_DEVICE` | Query device parameters |
| `IOCTL_IMDISK_QUERY_DRIVER` | Query driver information |
| `IOCTL_IMDISK_SET_DEVICE_FLAGS` | Modify device flags |
| `IOCTL_IMDISK_REMOVE_DEVICE` | Remove virtual disk |
| `IOCTL_IMDISK_REFERENCE_HANDLE` | Reference a handle in driver |
| `IOCTL_IMDISK_GET_REFERENCED_HANDLE` | Get referenced handle |
| `IOCTL_IMDISK_IOCTL_PASS_THROUGH` | Pass IOCTL to underlying device |
| `IOCTL_IMDISK_FSCTL_PASS_THROUGH` | Pass FSCTL to underlying device |

---

## Proxy Protocol

The proxy protocol uses a simple request/response structure:

### Request Types

```c
typedef enum _IMDPROXY_REQ {
    IMDPROXY_REQ_NULL,      // No operation
    IMDPROXY_REQ_INFO,      // Query disk information
    IMDPROXY_REQ_READ,      // Read data
    IMDPROXY_REQ_WRITE,     // Write data
    IMDPROXY_REQ_CONNECT,   // Connect to storage
    IMDPROXY_REQ_CLOSE,     // Close connection
    IMDPROXY_REQ_UNMAP,     // TRIM/Unmap
    IMDPROXY_REQ_ZERO,      // Zero-fill
    IMDPROXY_REQ_SCSI,      // SCSI pass-through
    IMDPROXY_REQ_SHARED     // Shared access operations
} IMDPROXY_REQ;
```

### Protocol Sequence

```mermaid
sequenceDiagram
    participant Driver as Kernel Driver
    participant Proxy as Proxy Server

    Driver->>Proxy: IMDPROXY_REQ_CONNECT + connection_string
    Proxy-->>Driver: IMDPROXY_CONNECT_RESP (error_code, object_ptr)
    
    Driver->>Proxy: IMDPROXY_REQ_INFO
    Proxy-->>Driver: IMDPROXY_INFO_RESP (file_size, alignment, flags)

    loop I/O Operations
        Driver->>Proxy: IMDPROXY_REQ_READ (offset, length)
        Proxy-->>Driver: IMDPROXY_READ_RESP (errorno, length) + data
        
        Driver->>Proxy: IMDPROXY_REQ_WRITE (offset, length) + data
        Proxy-->>Driver: IMDPROXY_WRITE_RESP (errorno, length)
    end

    Driver->>Proxy: IMDPROXY_REQ_CLOSE
```

---

## Summary

The ImDisk architecture follows a layered design:

1. **User Interface Layer**: CLI (`imdisk.exe`), CPL (`imdisk.cpl`), .NET (`ImDiskNet`)
2. **API Layer**: IOCTL interface, P/Invoke wrappers
3. **Kernel Layer**: Virtual disk driver (`imdisk.sys`), AWE driver (`awealloc.sys`)
4. **Proxy Layer**: Service (`ImDskSvc`), Protocol implementation
5. **Storage Layer**: Files, memory, network, physical RAM

The modular design allows for:
- Multiple storage backends (file, memory, proxy)
- Multiple device types (HDD, floppy, CD-ROM)
- Remote storage via proxy protocol
- High-performance RAM disks via AWE

---

## References

- **Microsoft Virtual Disk API**: https://docs.microsoft.com/en-us/windows/win32/api/virtdisk/
- **Windows Driver Kit (WDK)**: https://docs.microsoft.com/en-us/windows-hardware/drivers/
- **ImDisk Wiki**: https://github.com/LTRData/ImDisk/wiki

---

*Document generated for ImDisk codebase analysis. Original ImDisk source by Olof Lagerkvist.*
