# Code highlighting

Code blocks are highlighted by highlight.js (every language it ships). Unlabelled blocks and
unknown languages stay plain.

```swift
import Foundation

/// A documented type.
@MainActor final class Greeter: NSObject {
    let greeting = "hello" // a comment with "quotes" and let
    var count: Int = 42

    func greet(name: String) async throws -> String {
        let url = "https://example.com/\(name)"
        /* a block comment
           over two lines */
        return "\(greeting), \(name)! \(count + 1) \(url)"
    }
}
print(Greeter().greeting)
```

```python
from dataclasses import dataclass

@dataclass
class Port:
    name: str
    vlan: int = 1

def describe(port: Port) -> str:
    """Docstring over
    two lines."""
    return f"{port.name} in VLAN {port.vlan}"  # comment
```

```bash
#!/bin/bash
set -euo pipefail
for file in "$HOME"/*.md; do
    echo "Reading ${file}" >&2
    grep -c "needle" "$file" || true
done
```

```yaml
name: Hashlight
version: 1.2.0
enabled: true # comment
items:
  - "quoted"
  - plain
```

```json
{"name": "Hashlight", "version": 3, "notarized": false, "tags": ["viewer", null]}
```

```sql
SELECT name, COUNT(*) AS total
FROM ports
WHERE vlan IN (10, 20) -- comment
GROUP BY name;
```

```diff
- removed line
+ added line
  unchanged line
```

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache curl
CMD ["sh", "-c", "echo ready"]
```

```nginx
server {
    listen 443 ssl;
    location / { proxy_pass http://127.0.0.1:8080; }
}
```

```routeros
/ip address add address=192.0.2.1/24 interface=ether1 comment="uplink"
```

```
Plain block without a language: interface 1/1/1, vlan 10.
```
