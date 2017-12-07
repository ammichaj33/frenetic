open! Core
open Frenetic.Network
open Syntax
open Symbolic

(*===========================================================================*)
(* TOPOLOGY PARSING & PROCESSING                                             *)
(*===========================================================================*)

(** Certain information about the topology is tedious to extract from the graph
    every time. Thus we compute it once and for all and cache it in a more
    accessible format.
*)
type topo = {
  graph : Frenetic.Network.Net.Topology.t;
  switch_tbl : Net.Topology.vertex Int.Table.t; (* sw id -> vertex *)
  edge_tbl : Net.Topology.edge Int2.Table.t;    (* src_sw,dst_sw -> edge *)
  hop_tbl : Net.Topology.edge Int2.Table.t;     (* src_sw,src_pt -> out edge *)
}

let parse_topo (base_name : string) : topo =
  let file = base_name ^ ".dot" in
  let topo = Net.Parse.from_dotfile file in

  (* switch id to switch node map *)
  let switch_tbl : Net.Topology.vertex Int.Table.t =
    let open Net.Topology in
    let tbl = Int.Table.create () in
    iter_vertexes (fun v ->
      if Topology.is_switch topo v then
        let id = Topology.sw_val topo v in
        Hashtbl.add_exn tbl ~key:id ~data:v
    )
      topo;
    tbl
  in

  (* (src_sw,dst_sw) |-> edge *)
  let edge_tbl : Net.Topology.edge Int2.Table.t =
    let tbl = Int2.Table.create () in
    Net.Topology.iter_edges (fun edge ->
      let (src,_) = Net.Topology.edge_src edge in
      let (dst,_) = Net.Topology.edge_dst edge in
      if Topology.(is_switch topo src && is_switch topo dst) then
        let key = Topology.(sw_val topo src, sw_val topo dst) in
        Hashtbl.add_exn tbl ~key ~data:edge
    )
      topo;
    tbl
  in

  (* (sw,pt) |-> out edge *)
  let hop_tbl : Net.Topology.edge Int2.Table.t =
    let tbl = Int2.Table.create () in
    Net.Topology.iter_edges (fun edge ->
      let (src_sw, src_pt) = Net.Topology.edge_src edge in
      if Topology.is_switch topo src_sw then
        let key = Topology.(sw_val topo src_sw, pt_val src_pt) in
        Hashtbl.add_exn tbl ~key ~data:edge
      )
      topo;
    tbl
  in

  { graph = topo; switch_tbl; edge_tbl; hop_tbl; }




(*===========================================================================*)
(* ROUTING SCHEME PARSING & PROCESSING                                       *)
(*===========================================================================*)

let parse_sw sw =
  assert (String.get sw 0 = 's');
  String.slice sw 1 (String.length sw)
  |> Int.of_string

(* switch to port mapping *)
let parse_trees topo file : (int list) Int.Table.t =
  let tbl = Int.Table.create () in
  In_channel.(with_file file ~f:(iter_lines ~f:(fun l ->
    let l = String.strip l in
    if not (String.get l 0 = '#') then
    match String.split ~on:' ' l with
    | [src; "--"; dst] ->
      let src = parse_sw src in
      let dst = parse_sw dst in
      let edge = Hashtbl.find_exn topo.edge_tbl (src,dst) in
      let (_, out_port) = Net.Topology.edge_src edge in
      (* find destination port *)
      Hashtbl.add_multi tbl ~key:src ~data:(Topology.pt_val out_port)
    | _ ->
      failwith "unexpected format"
  )));
  Hashtbl.iteri tbl ~f:(fun ~key:sw ~data:pts ->
    printf "sw %d: %s\n" sw (List.to_string pts ~f:Int.to_string)
  );
  tbl

(* switch to port mapping *)
let parse_nexthops topo file : (int list) Int.Table.t =
  let tbl = Int.Table.create () in
  In_channel.(with_file file ~f:(iter_lines ~f:(fun l ->
    let l = String.strip l in
    if not (String.get l 0 = '#') then
    match String.split ~on:' ' l with
    | src::":"::dsts ->
      let src = parse_sw src in
      List.map dsts ~f:(fun dst ->
        let dst = parse_sw dst in
        let edge = Hashtbl.find_exn topo.edge_tbl (src,dst) in
        let (_, out_port) = Net.Topology.edge_src edge in
        Topology.pt_val out_port
      )
      |> fun data -> Hashtbl.add_exn tbl ~key:src ~data
    | _ ->
      failwith "unexpected format"
  )));
  tbl

open Params

(* am I at a good port? *)
let at_good_pt sw pts = PNK.(
  List.map pts ~f:(fun pt_val -> ???(pt,pt_val) & ???(up sw pt_val, 1))
  |> mk_big_disj
)

(* given a current switch and the inport, what tree are we on? *)
let mk_current_tree_tbl topo (port_tbl : (int list) Int.Table.t) : int Int2.Table.t =
  let tbl = Int2.Table.create () in
  (* the port map maps a switch to the out_ports in order of the tree preference *)
  Hashtbl.iteri port_tbl ~f:(fun ~key:src_sw ~data:src_pts ->
    List.iteri src_pts ~f:(fun i src_pt ->
      (* if we are on tree i, we go from src_sw to src_pt across the following edge: *)
      let edge = Hashtbl.find_exn topo.hop_tbl (src_sw, src_pt) in
      (* thus, we would end up at the following switch: *)
      let (dst_sw, dst_pt) = Net.Topology.edge_dst edge in
      (* thus, we can infer from entering switch `dst_sw` at port `dst_pt` that
         we must be on tree i
      *)
      let key = Topology.(sw_val topo.graph dst_sw, Topology.pt_val dst_pt) in
      Hashtbl.add_exn tbl ~key ~data:i
    )
  );
  (* for ingress ports, simply start at tree 0 *)
  List.iter (Topology.ingress_locs topo.graph ~dst:destination) ~f:(fun (sw, pt_val) ->
    let key = (Topology.sw_val topo.graph sw, pt_val) in
    Hashtbl.add_exn tbl ~key ~data:0
  );
  tbl



(*===========================================================================*)
(* ROUTING SCHEMES                                                           *)
(*===========================================================================*)

let random_walk base_name : Net.Topology.vertex -> string policy =
  let topo = parse_topo base_name in
  fun sw ->
    Topology.vertex_to_ports topo.graph sw ~dst_filter:(Topology.is_switch topo.graph)
    |> List.map ~f:(fun out_pt_id -> PNK.( !!(pt, Topology.pt_val out_pt_id) ))
    |> PNK.uniform

let resilient_random_walk base_name : Net.Topology.vertex -> string policy =
  let topo = parse_topo base_name in
  fun sw -> 
    let pts =
      Topology.vertex_to_ports topo.graph sw
      |> List.map ~f:Topology.pt_val
    in
    let choose_port = random_walk topo sw in
    PNK.( do_whl (neg (at_good_pt sw pts)) choose_port )

let shortest_path base_name : Net.Topology.vertex -> string policy =
  let topo = parse_topo base_name in
  let port_tbl = parse_trees topo (base_name ^ "-spf.trees") in
  fun sw ->
    let sw_val = Topology.sw_val topo.graph sw in
    match Hashtbl.find port_tbl sw_val with
    | Some (pt_val::_) -> PNK.( !!(pt, pt_val) )
    | _ ->
      eprintf "switch %d cannot reach destination\n" sw_val;
      failwith "network disconnected!"

let ecmp base_name : Net.Topology.vertex -> string policy =
  let topo = parse_topo base_name in
  let port_tbl = parse_nexthops topo (base_name ^ "-allsp.nexthops") in
  fun sw ->
    let sw_val = Topology.sw_val topo.graph sw in
    match Hashtbl.find port_tbl sw_val with
    | Some pts -> PNK.(
        List.map pts ~f:(fun pt_val -> !!(pt, pt_val))
        |> uniform
      )
    | _ ->
      eprintf "switch %d cannot reach destination\n" sw_val;
      failwith "network disconnected!"

let resilient_ecmp base_name : Net.Topology.vertex -> string policy =
  let topo = parse_topo base_name in
  let port_tbl = parse_nexthops topo (base_name ^ "-allsp.nexthops") in
  fun sw ->
    let sw_val = Topology.sw_val topo sw in
    match Hashtbl.find port_tbl sw_val with
    | Some pts -> PNK.(
        do_whl (neg (at_good_pt sw pts)) (
          List.map pts ~f:(fun pt_val -> !!(pt, pt_val))
          |> uniform
        )
      )
    | _ ->
      eprintf "switch %d cannot reach destination\n" sw_val;
      failwith "network disconnected!"

let car base_name ~(style: [`Deterministic|`Probabilistic])
  : Net.Topology.vertex -> int -> string policy =
  let topo = parse_topo base_name in
  let port_tbl = parse_trees topo (base_name ^ "-disjointtrees.trees") in
  let current_tree_tbl = mk_current_tree_tbl topo port_tbl in
  let port_tbl = Int.Table.map port_tbl ~f:Array.of_list in
  fun sw in_pt ->
    let sw_val = Topology.sw_val topo sw in
    match Hashtbl.find current_tree_tbl (sw_val, in_pt) with
    | None ->
      (* eprintf "verify that packets never enter switch %d at port %d\n" sw_val in_pt; *)
      PNK.( drop )
    | Some i ->
      let pts = Hashtbl.find_exn port_tbl sw_val in
      begin match style with
      | `Deterministic ->
        let n = Array.length pts in
        (* the order in which we should try ports, i.e. starting from i *)
        let pts = Array.init n (fun j -> pts.((i+j) mod n)) in
        PNK.(
          Array.to_list pts
          |> ite_cascade ~otherwise:drop ~f:(fun pt_val ->
              let guard = ???(up sw_val pt_val, 1) in
              let body = !!(pt, pt_val) in
              (guard, body)
            )
        )
      | `Probabilistic ->
        failwith "not implemented"
      end