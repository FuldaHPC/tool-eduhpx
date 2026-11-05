# Example run files

Open them with the viewer (*File > Examples* has the first three built in).

| File | Program | What it shows |
|---|---|---|
| `flat_broadcast_16loc_4nodes.csv` | 20 flat broadcasts of 64 KiB | the root answers 15 requests one by one |
| `hierarchical_broadcast_16loc_4nodes.csv` | 20 hierarchical broadcasts (binary tree) | every node asks its parent, data moves down the tree |
| `mixed_4loc_1node.csv` | mixed point-to-point traffic, no collective | bursts of messages |

The files were made from merged runs of the first EduHPX prototype (`tools/json_to_csv.py`). More examples (all
collectives, flat and hierarchical, on 4 or more nodes) will follow from runs with the scripts.
