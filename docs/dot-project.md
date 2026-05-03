# dot-project

[View script](../dot-project)

Generate `.project` files for Salesforce B2C Commerce cartridge directories so Eclipse-based tooling (like UX Studio) can detect and open them as projects.

In SFCC development, cartridges live as subdirectories under a code version directory. Each one needs a `.project` file with Eclipse project metadata -- specifically, the `com.demandware.studio.core.beehiveNature` nature and the `com.demandware.studio.core.beehiveElementBuilder` builder. This script writes that XML file into each subdirectory, using the directory name as the project name.

If you've cloned a code version from version control and your IDE isn't detecting the cartridges, or you've created new cartridge directories by hand, this will fix it.

## Quick start

Run it in the directory containing your cartridges (typically a code version directory):

```
$ cd /path/to/Sites/site_name/version_123
$ dot-project
Generated ./app_storefront_base/.project
Generated ./bc_shipstation/.project
Generated ./int_custom_integration/.project
```

Or pass the code version directory as an argument:

```
$ dot-project /path/to/Sites/site_name/version_123
Generated /path/to/Sites/site_name/version_123/app_storefront_base/.project
Generated /path/to/Sites/site_name/version_123/bc_shipstation/.project
Generated /path/to/Sites/site_name/version_123/int_custom_integration/.project
```

## Common examples

**Generate for all cartridges in the current directory:**

```
$ dot-project
```

Walks through every subdirectory and writes a `.project` file in each one.

**Generate for cartridges in a specific code version:**

```
$ dot-project ~/Sites/RefArch/version_1
```

Useful if you want to run it from somewhere else or script it across multiple code versions.

## The .project file structure

Each `.project` file is standard Eclipse XML:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>app_storefront_base</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>com.demandware.studio.core.beehiveElementBuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>com.demandware.studio.core.beehiveNature</nature>
    </natures>
</projectDescription>
```

The `<name>` element comes from the cartridge directory name. The nature (`beehiveNature`) and builder (`beehiveElementBuilder`) are what UX Studio looks for to identify a directory as a B2C Commerce cartridge project.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `code_version_directory` | Directory containing cartridge subdirectories (default: current directory) |
| `-h, --help` | Display help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Always (see note below) |

The script continues processing even if one cartridge fails. Per-file write errors are logged to stderr but do not affect the final exit code. If you need partial-failure detection, check stderr.

### Dependencies

None -- uses only bash builtins and standard Unix utilities (`basename`, `cat`).
