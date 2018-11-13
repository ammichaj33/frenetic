(** Module with static parameters *)
open! Core

(** number of worker processes *)
let j = 16

(** switch field *)
let sw = "sw"

(** port field *)
let pt = "pt"

(** counter field *)
let counter = "failures"

(** ttl field *)
let ttl = "ttl"
let max_ttl = 32

(** Destination host. Files generated by Praveen assume this is 1. *)
let destination = 1

(** up bit associated with link *)
let up sw pt = sprintf "up_%d" pt
let is_up_field f = String.is_prefix ~prefix:"up_" f

(** Extra bit needed for F10 scheme 2 re-routing *)
let f10s2 = "f10s2"

(** equivalence should be modulo these fields *)
let modulo =
  [pt; counter; f10s2; ttl]

(** various files *)
let topo_file base_name = base_name ^ ".dot"
let spf_file base_name = base_name ^ "-spf.trees"
let ecmp_file base_name = base_name ^ "-allsp.nexthops"
let car_file base_name = base_name ^ "-disjointtrees.trees"
let log_file base_name = base_name ^ ".log"
let dump_file ?(ext="json") base_name ~routing_scheme ~max_failures ~failure_prob =
  let scheme = String.tr routing_scheme ~target:' ' ~replacement:'_' in
  let dir, topology = Filename.split base_name in
  let dir = sprintf "%s/results/%s-%s" dir topology scheme in
  let mf = if max_failures < 0 then "inf" else Int.to_string max_failures in
  let p_num, p_den = Prob.to_int_frac failure_prob in
  sprintf "%s/%s-%d-%d.%s" dir mf p_num p_den ext
let dot_file  =
 dump_file ~ext:"dot"

