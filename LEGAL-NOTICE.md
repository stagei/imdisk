# Legal Notice: Forking and Modifying ImDisk

## Original Project License

**ImDisk Virtual Disk Driver** by Olof Lagerkvist (LTRData) is licensed under the **GNU General Public License v2 (GPL-2.0)**.

- Repository: https://github.com/LTRData/ImDisk
- Original Author: Olof Lagerkvist
- License: GPL-2.0

---

## Can You Fork, Modify, and Redistribute?

### ✅ YES, You Can:

| Action | Permitted | Conditions |
|--------|-----------|------------|
| Fork the code | ✅ Yes | Must keep GPL-2.0 license |
| Modify the code | ✅ Yes | Must document changes |
| Convert to .NET 10 | ✅ Yes | Derivative work remains GPL-2.0 |
| Convert to C# | ✅ Yes | Derivative work remains GPL-2.0 |
| Rewrite in modern C++ | ✅ Yes | Derivative work remains GPL-2.0 |
| Distribute your version | ✅ Yes | Must include source code |
| Use your own project name | ✅ Yes | Must acknowledge original |
| Sign with your certificate | ✅ Yes | No license restrictions |
| Charge for distribution | ✅ Yes | Source must still be free |

### ❌ NO, You Cannot:

| Action | Permitted | Reason |
|--------|-----------|--------|
| Make it proprietary | ❌ No | GPL-2.0 is copyleft |
| Remove the GPL license | ❌ No | Derivative works must be GPL |
| Hide the source code | ❌ No | Source must be available |
| Claim sole authorship | ❌ No | Must credit original author |
| Sublicense under different terms | ❌ No | Must remain GPL-2.0 |

---

## GPL-2.0 Key Requirements

When you create a derivative work based on GPL-2.0 code, you **must**:

1. **Keep the GPL-2.0 License**
   - Your derivative work must also be licensed under GPL-2.0
   - Include a copy of the GPL-2.0 license with your distribution

2. **Provide Source Code**
   - You must make source code available to anyone who receives your binaries
   - This can be via download link, included in package, or written offer

3. **Document Your Changes**
   - Modified files must carry prominent notices stating you changed them
   - Include the date of any changes

4. **Credit the Original Author**
   - Keep existing copyright notices intact
   - Add your own copyright for your modifications

5. **No Additional Restrictions**
   - You cannot impose restrictions beyond what GPL-2.0 allows
   - Recipients get the same rights you received

---

## How to Properly Credit

### In Your README.md:

```markdown
## Acknowledgments

This project is a derivative work based on **ImDisk Virtual Disk Driver** 
by Olof Lagerkvist (LTRData).

- Original Project: https://github.com/LTRData/ImDisk
- Original Author: Olof Lagerkvist
- Original License: GPL-2.0

This derivative work is also licensed under GPL-2.0.
```

### In Your Source Files:

```csharp
// This file is part of [Your Project Name]
// Copyright (C) 2026 [Your Name/Company]
//
// Based on ImDisk Virtual Disk Driver
// Copyright (C) Olof Lagerkvist
// https://github.com/LTRData/ImDisk
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
```

---

## Recommended Project Structure

```
YourProjectName/
├── LICENSE                 # GPL-2.0 license text
├── README.md              # With acknowledgments section
├── NOTICE.md              # Attribution to original authors
├── CHANGELOG.md           # Document your changes
├── src/
│   ├── Core/              # Your modern C#/.NET 10 code
│   └── Driver/            # Your C++ driver code (if any)
└── original/              # (Optional) Original code for reference
```

---

## Naming Your Derivative

You can create your own project name, but be clear about the relationship:

### ✅ Good Examples:
- "VirtualDiskPlus - A modern fork of ImDisk"
- "DiskMount.NET - Based on ImDisk Virtual Disk Driver"
- "ImDisk Modern - .NET 10 port of ImDisk"

### ❌ Avoid:
- Implying you created the original concept
- Removing all references to ImDisk/LTRData
- Suggesting the original author endorses your fork

---

## Commercial Use

**GPL-2.0 allows commercial use**, but with conditions:

- You CAN sell your derivative work
- You CAN offer paid support/services
- You CAN include it in commercial products
- You MUST still provide source code under GPL-2.0
- You CANNOT make the code proprietary

### Business Models That Work with GPL-2.0:
- Sell support and services
- Dual licensing (if you own all the code)
- SaaS (service, not distribution)
- Consulting and customization
- Hardware bundling

---

## Summary

| Question | Answer |
|----------|--------|
| Can I fork and modify? | ✅ Yes |
| Can I convert to .NET 10/C#? | ✅ Yes |
| Can I use my own project name? | ✅ Yes |
| Can I sell it? | ✅ Yes (with source) |
| Can I make it proprietary? | ❌ No |
| Must I credit original author? | ✅ Yes |
| Must I use GPL-2.0? | ✅ Yes |
| Must I provide source code? | ✅ Yes |

---

## Disclaimer

This document is for informational purposes only and does not constitute legal advice. For specific legal questions about GPL-2.0 compliance, consult a qualified attorney.

---

## References

- [GPL-2.0 Full Text](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- [GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html)
- [Original ImDisk Project](https://github.com/LTRData/ImDisk)
- [Choose a License - GPL-2.0](https://choosealicense.com/licenses/gpl-2.0/)

---

*Document created: January 27, 2026*
*For project: https://github.com/stagei/imdisk*
