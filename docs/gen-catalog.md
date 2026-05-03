# gen-catalog

[View script](../gen-catalog)

Generate SFCC catalog XML files for testing and development. Creates well-formed Demandware impex XML with base products, variants, and variant relationships -- useful for seeding sandbox environments, QA testing, or development data loads without hand-crafting XML.

The output is valid for upload via Business Manager or the SFCC OCAPI Data API.

## Quick start

```
$ gen-catalog 2 3
<?xml version="1.0" encoding="UTF-8"?>
<catalog xmlns="http://www.demandware.com/xml/impex/catalog/2006-10-31"
         xmlns:xml="http://www.w3.org/XML/1998/namespace"
         catalog-id="test-catalog">
    <header/>
    <product product-id="BASE1">
        <display-name xml:lang="en">BASE1</display-name>
        <variations>
            <variants>
                <variant product-id="BASE1-VAR-001" default="true"/>
                <variant product-id="BASE1-VAR-002"/>
                <variant product-id="BASE1-VAR-003"/>
            </variants>
        </variations>
    </product>
    <product product-id="BASE1-VAR-001">
        <display-name xml:lang="en">BASE1 Variant 001</display-name>
    </product>
    <product product-id="BASE1-VAR-002">
        <display-name xml:lang="en">BASE1 Variant 002</display-name>
    </product>
    ...
</catalog>
```

That creates 2 base products (BASE1, BASE2), each with 3 variants.

## Common examples

**Redirect to a file:**

```bash
gen-catalog 10 5 > catalog.xml
```

**Specify a custom catalog ID:**

```bash
gen-catalog 3 2 my-sandbox-catalog
```

**Generate a large test catalog for performance testing:**

```bash
gen-catalog 1000 20 perf-test-catalog > large-catalog.xml
```

## Catalog structure

Each base product contains a `<variations>` block listing its variant product IDs. Variant products are defined separately as standard `<product>` elements.

Product IDs follow this pattern:
- Base: `BASE1`, `BASE2`, `BASE3`, ...
- Variants: `BASE1-VAR-001`, `BASE1-VAR-002`, ...

The first variant of each base is marked `default="true"`.

Display names are set to the product ID (for bases) or `BASE# Variant ###` (for variants). In practice you'd enrich these via subsequent XML loads or Business Manager edits.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `base_count` | Number of base products to generate (required, positive integer) |
| `variants_per_base` | Number of variants per base product (required, positive integer) |
| `catalog_id` | Catalog ID attribute in the XML (optional, defaults to `test-catalog`) |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (missing required args, non-numeric values, zero or negative counts) |

### Dependencies

None -- uses only bash builtins and standard Unix utilities.
