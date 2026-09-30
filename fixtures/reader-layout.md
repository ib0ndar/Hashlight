# Reader Layout Fixture

Use this document to check rendered content width, page margins, vertical rhythm, and table wrapping.

The reader view should keep a comfortable line length in **Narrow** mode and use the available pane in **Full** mode. Technical values such as `ethernet1/1/24` and `aa:bb:cc:dd:ee:ff` should remain legible when there is room.

## Lists

- Compact bullet item
- A longer bullet item with enough prose to wrap naturally inside the selected reading width
- Inline code: `show interfaces status`

1. First numbered item
2. Second numbered item with a [reference link](https://example.com/networking)

## Blockquote and code

> A reader-oriented preview should preserve normal paragraph wrapping and leave clear margins around the page.

```text
Interface        Admin  Oper  Speed   VLAN
ethernet1/1/24   up     up    100G    1234
```

## Image

![Hashlight icon](../Hashlight/Assets.xcassets/AppIcon.appiconset/512.png)

## Compact table

| VLAN | State | Speed |
|------|-------|-------|
| 1234 | Up | 100 Gbps |
| 4094 | Down | 25 Gbps |

## Wide technical table

| Interface | Description | Admin State | Operational State | Speed | Duplex | VLAN | MAC Address | IPv4 Address | Documentation |
|-----------|-------------|-------------|-------------------|-------|--------|------|-------------|--------------|---------------|
| `ethernet1/1/1` | Very long interface description used to check that prose receives the flexible width and wraps within the table. | Enabled | Up | 100 Gbps | Full | 1234 | `aa:bb:cc:dd:ee:ff` | `192.0.2.14/24` | [Switch reference](https://example.com/interfaces/ethernet1/1/1) |
| `ethernet1/1/2` | Uplink toward the aggregation switch with deliberately long descriptive text to exercise wrapping at several window widths. | Enabled | Down | 25 Gbps | Full | 4094 | `11:22:33:44:55:66` | `198.51.100.27/24` | [Port guide](https://example.com/networking/ports) |
| `port-channel100` | Core-facing bundle used for a long identifier and a long description in the same row. | Disabled | Down | 2 x 100 Gbps | Full | 2000 | `02:00:00:00:00:64` | `203.0.113.100/24` | [LAG notes](https://example.com/lags) |

## Closing content

The page should continue naturally after both tables, without forcing the entire preview to scroll horizontally.
