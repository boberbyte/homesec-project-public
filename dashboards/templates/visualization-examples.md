# Kibana Visualization Examples

## Common Visualizations for HomeSec

### 1. Alert Count Over Time (Line Chart)

```json
{
  "title": "Alerts Over Time",
  "type": "line",
  "params": {
    "type": "line",
    "grid": {"categoryLines": false},
    "categoryAxes": [{
      "id": "CategoryAxis-1",
      "type": "category",
      "position": "bottom",
      "show": true,
      "style": {},
      "scale": {"type": "linear"},
      "labels": {"show": true, "filter": true, "truncate": 100},
      "title": {}
    }],
    "valueAxes": [{
      "id": "ValueAxis-1",
      "name": "LeftAxis-1",
      "type": "value",
      "position": "left",
      "show": true,
      "style": {},
      "scale": {"type": "linear", "mode": "normal"},
      "labels": {"show": true, "rotate": 0, "filter": false, "truncate": 100},
      "title": {"text": "Alert Count"}
    }],
    "seriesParams": [{
      "show": "true",
      "type": "line",
      "mode": "normal",
      "data": {"label": "Alert Count", "id": "1"},
      "valueAxis": "ValueAxis-1",
      "drawLinesBetweenPoints": true,
      "showCircles": true
    }],
    "addTooltip": true,
    "addLegend": true,
    "legendPosition": "right",
    "times": [],
    "addTimeMarker": false
  },
  "aggs": [
    {
      "id": "1",
      "enabled": true,
      "type": "count",
      "schema": "metric",
      "params": {}
    },
    {
      "id": "2",
      "enabled": true,
      "type": "date_histogram",
      "schema": "segment",
      "params": {
        "field": "@timestamp",
        "interval": "auto",
        "min_doc_count": 1
      }
    }
  ],
  "filter": {
    "query": "_index:homesec-ids-* AND event_type:alert"
  }
}
```

### 2. Top Alert Signatures (Bar Chart)

**Query**: `_index:homesec-ids-* AND event_type:alert`

**Aggregations**:
- Y-axis: Count
- X-axis: Terms aggregation on `alert.signature.keyword`
- Size: 10
- Order: Descending by count

### 3. Alert Severity Distribution (Pie Chart)

**Query**: `_index:homesec-ids-* AND event_type:alert`

**Aggregations**:
- Slice size: Count
- Split slices: Terms on `alert.severity`

**Color mapping**:
- Severity 1 (High): Red
- Severity 2 (Medium): Orange
- Severity 3 (Low): Yellow

### 4. Geographic Attack Map

**Query**: `_index:homesec-ids-* AND event_type:alert`

**Type**: Coordinate Map

**Aggregations**:
- Geohash aggregation on `geoip.location`
- Metric: Count

**Note**: Requires GeoIP processor in Elasticsearch ingest pipeline.

### 5. Top Attacker IPs (Data Table)

**Query**: `_index:homesec-ids-* AND event_type:alert`

**Columns**:
1. Source IP: `src_ip.keyword`
2. Alert Count: Count aggregation
3. Unique Destinations: Cardinality on `dest_ip`
4. Countries: Terms on `geoip.country_name`

### 6. DNS Query Volume (Area Chart)

**Query**: `_index:homesec-dns-* AND event_type:dns`

**Aggregations**:
- Y-axis: Count
- X-axis: Date histogram on `@timestamp` (interval: auto)
- Split series: Terms on `dns.type`

### 7. System CPU Usage (Gauge)

**Query**: `_index:homesec-metrics-* AND system.cpu.user.pct:*`

**Type**: Gauge

**Metric**: Average of `system.cpu.user.pct`

**Ranges**:
- 0-50%: Green
- 50-80%: Yellow
- 80-100%: Red

### 8. Protocol Distribution (Donut Chart)

**Query**: `_index:homesec-ids-* AND proto:*`

**Aggregations**:
- Slice size: Count
- Split slices: Terms on `proto.keyword`

**Top protocols**: TCP, UDP, ICMP, HTTP, TLS, DNS, SSH

### 9. Honeypot Attack Timeline (Heatmap)

**Query**: `dest_ip:192.168.99.10 AND event_type:alert`

**Type**: Heat Map

**Aggregations**:
- X-axis: Date histogram (1 hour interval)
- Y-axis: Terms on `alert.category`
- Metric: Count

### 10. Bandwidth Usage (Line Chart with Multiple Series)

**Query**: `_index:homesec-metrics-* AND network.in.bytes:*`

**Aggregations**:
- Y-axis: Sum of `network.in.bytes` and `network.out.bytes`
- X-axis: Date histogram on `@timestamp`
- Split series: Terms on `host.name`

## Query Examples

### Lucene Queries

```
# High severity alerts
alert.severity:1

# Alerts from specific IP
src_ip:"192.168.10.100"

# HTTP alerts
proto:"HTTP" AND event_type:"alert"

# DNS queries to suspicious TLDs
dns.query:*.tk OR dns.query:*.xyz OR dns.query:*.ml

# Large file transfers
fileinfo.size:>10000000
```

### KQL (Kibana Query Language) Queries

```
# High severity alerts
alert.severity: 1

# Alerts from IP range
src_ip: 192.168.10.0/24

# HTTP alerts with status 200
proto: "HTTP" and http.status: 200

# DNS queries NOT to Google DNS
event_type: dns and not dest_ip: (8.8.8.8 or 8.8.4.4)

# Files with specific extensions
fileinfo.filename: *.exe or fileinfo.filename: *.dll
```

### Aggregation Examples

```json
{
  "aggs": {
    "top_attackers": {
      "terms": {
        "field": "src_ip.keyword",
        "size": 10,
        "order": {"_count": "desc"}
      },
      "aggs": {
        "unique_targets": {
          "cardinality": {
            "field": "dest_ip.keyword"
          }
        }
      }
    }
  }
}
```

## Time-based Filters

- Last 15 minutes: `now-15m`
- Last hour: `now-1h`
- Last 24 hours: `now-24h` (default)
- Last 7 days: `now-7d`
- Last 30 days: `now-30d`
- Today: `now/d to now`
- This week: `now/w to now`
- This month: `now/M to now`

## Field Formatting

### Bytes to Human Readable

```
Format: Bytes
Pattern: 0.00 b
```

### Percentage

```
Format: Percentage
Pattern: 0.00%
```

### Duration

```
Format: Duration
Input: Milliseconds
Output: Human readable (e.g., "5m 30s")
```

## Tips for Creating Effective Visualizations

1. **Choose the right visualization type**:
   - Time series → Line chart
   - Comparisons → Bar chart
   - Distributions → Pie/Donut chart
   - Single value → Metric/Gauge
   - Geographic → Map
   - Correlation → Heat map

2. **Use appropriate aggregations**:
   - Count: Number of documents
   - Sum: Total of numeric field
   - Average: Mean value
   - Min/Max: Extremes
   - Cardinality: Unique count
   - Percentiles: Distribution analysis

3. **Apply filters**:
   - Use index patterns to limit data
   - Add query filters for specific conditions
   - Use time filters for relevant time ranges

4. **Optimize performance**:
   - Limit data with filters
   - Use appropriate time ranges
   - Aggregate high-cardinality fields carefully
   - Cache frequently accessed visualizations

5. **Make it actionable**:
   - Add drilldowns to details
   - Link related dashboards
   - Include context and descriptions
   - Set up alerts for anomalies
