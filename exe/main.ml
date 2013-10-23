open DOT_Types
open Topology

type modeType =
  | DotMode
  | DefaultMode

let infname = ref ""
let mode = ref DefaultMode

let arg_spec =
  [
    ("--dot",
     Arg.Unit (fun () -> mode := DotMode),
     "\tParse a file in DOT format"
    )
]

let usage = Printf.sprintf "usage: %s [OPTIONS] filename" Sys.argv.(0)

let _ =
  Arg.parse
    arg_spec
    (fun fn -> infname := fn)
    usage ;
  Printf.printf "Attempting to topology from file: %s\n%!" !infname;
  let topo = match !mode with
    | DotMode -> Printf.printf "Entering DotMode\n"; DOT_Parser.dot_parse !infname
    | DefaultMode -> DOT_Parser.dot_parse !infname
  in
  Printf.printf "\n\nDOT representation: %s\n" (Topology.to_dot topo)
