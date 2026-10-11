# Offline coordinate coverage and conversion credits

`mainland-coverage.json` contains the complete `MultiPolygon` geometry for the
`GU_A3 == CHN` feature of Natural Earth 5.1.1's 1:10 million admin-0 map units.
No geometric simplification was applied; source coordinate precision is kept.
The CHN map unit includes Hainan. Hong Kong (HKG), Macau (MAC), Taiwan (TWN),
and neighboring map units were not selected.

- Source: <https://github.com/nvkelso/natural-earth-vector/blob/v5.1.1/geojson/ne_10m_admin_0_map_units.geojson>
- Original source Git blob: `003025bf947f0c083318dfdb86a69b8dd0678947`
- Extracted JSON SHA-256 (LF line ending): `ec3fa27963f5e4481b6d68bdb9a132f48188dc5619df0a237dbdeac70009d2ec`
- License: public domain; full source notice in `NaturalEarth-LICENSE.txt`.

This is a geographic guard for an optional coordinate conversion, not a
survey-grade boundary dataset or a statement about legal borders. Natural
Earth's 1:10 million scale does not establish street-level conversion coverage;
points very close to borders or shorelines may be left unchanged. The app does
not use SIM, IP address, language or account region to infer coordinate systems.

The forward WGS84-to-GCJ-02 formula in `CoordinateTransform.swift` is a Swift
port of `wandergis/coordtransform` version 2.1.2, commit
`606c6f3b57b6f1d60458793fea39928d2b11b637`:
<https://github.com/wandergis/coordtransform/blob/606c6f3b57b6f1d60458793fea39928d2b11b637/index.js>.
The inverse uses iterative convergence. The bundled polygon replaces the
upstream rectangular geographic guard. The conversion is an engineering
approximation, not an official Apple algorithm. See `coordtransform-LICENSE.txt`
for the complete MIT notice.

Stored app coordinates and standard GPX use WGS84. Map rendering/point selection
and Apple search/routing service coordinate conventions are independent,
explicit compatibility settings whose defaults preserve standard coordinates.
These settings never rewrite saved places. Legacy records retain their exact
numbers; the first migration backs up the old serialized data. Only an explicit
per-place GCJ-02 interpretation changes an old favorite, and its original values
remain available for restoration.
