| Benchmark (twice - once) | run 1 | run 2 |
|---|---:|---:|
| `bench_generate_hex_cave_copy` | 1,141,153 | 1,141,153 |
| `bench_generate_hex_cave_open` | 1,033,617 | 1,033,617 |
| `bench_generate_hex_forest_copy` | 1,122,301 | 1,122,301 |
| `bench_generate_hex_forest_open` | 968,175 | 968,175 |
| `bench_generate_hex_meadow_copy` | 1,146,507 | 1,146,507 |
| `bench_generate_hex_meadow_open` | 991,591 | 991,591 |
| `bench_generate_hex_ruin_copy` | 1,121,301 | 1,121,301 |
| `bench_generate_hex_ruin_open` | 967,175 | 967,175 |
| `bench_generate_rect_cave_copy` | 430,004 | 430,004 |
| `bench_generate_rect_cave_open` | 436,014 | 436,014 |
| `bench_generate_rect_forest_copy` | 395,572 | 395,572 |
| `bench_generate_rect_forest_open` | 420,268 | 420,268 |
| `bench_generate_rect_meadow_copy` | 410,440 | 410,440 |
| `bench_generate_rect_meadow_open` | 435,136 | 435,136 |
| `bench_generate_rect_ruin_copy` | 420,078 | 420,078 |
| `bench_generate_rect_ruin_open` | 444,774 | 444,774 |
| `bench_grouped_window` | 193,584 | 193,584 |
| `bench_grouped_window_most` | 268,428 | 268,428 |
| `bench_grouped_window_six` | 223,362 | 223,362 |
| `bench_hex_layer` | 766,712 | 766,712 |
| `bench_hex_layer_six` | 695,533 | 695,533 |
| `bench_hex_origin` | 56,910 | 56,910 |
| `bench_hex_window` | 876,310 | 876,310 |
| `bench_hex_window_six` | 799,152 | 799,152 |
| `bench_rect_layer` | 39,434 | 39,434 |
| `bench_rect_origin` | 3,730 | 3,730 |
| `bench_rect_window` | 64,234 | 64,234 |
| `bench_table_window` | 318,044 | 318,044 |
| `bench_table_window_six` | 289,880 | 289,880 |

| Unit cost, per iteration | run 1 | run 2 |
|---|---:|---:|
| table lookup, `ROW` (a 3-tuple) | 1,370 | 1,370 |
| table lookup, a slot of 12 | 1,075 | 1,075 |
| table lookup, `Bits::pow` | 1,005 | 1,005 |
| loop iteration (with an addition) | 1,895 | 1,895 |
