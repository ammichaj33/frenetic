(* Student has seen repeater that emits packet-out messages. Now, emit
   a flow mod. *)
module MyApplication : Ox_Controller.OXMODULE = struct
  open Ox_Controller.OxPlatform
  open OpenFlow0x01

  let switch_connected (sw : switchId) : unit =
    Printf.printf "Switch %Ld connected.\n%!" sw
      
  let switch_disconnected (sw : switchId) : unit =
    Printf.printf "Switch %Ld disconnected.\n%!" sw
      
  let packet_in (sw : switchId) (xid : xid) (pk : PacketIn.t) : unit =
    Printf.printf "Received a PacketIn message from switch %Ld:\n%s\n%!"
      sw (PacketIn.to_string pk);
    (* FILL: Send the packet out of all ports. *)
    send_packet_out sw 0l
      { PacketOut.payload = pk.PacketIn.payload;
        PacketOut.port_id = None;
        (* TODO(arjun): warn in docs that Flood is *wrong* *)
        PacketOut.actions = [Action.Output PseudoPort.AllPorts]
      }

  let barrier_reply (sw : switchId) (xid : xid) : unit =
    Printf.printf "Received a barrier reply %ld.\n%!" xid

  let stats_reply (sw : switchId) (xid : xid) (stats : StatsReply.t) : unit =
    Printf.printf "Received a StatsReply from switch %Ld:\n%s\n%!"
      sw (StatsReply.to_string stats)

  let port_status (sw : switchId) (xid : xid) (port : PortStatus.t) : unit =
    Printf.printf "Received a PortStatus from switch %Ld:\n%s\n%!"
      sw (PortStatus.to_string port)

end

module Controller = Ox_Controller.Make (MyApplication)

let _ =
  Printf.printf "--- Welcome to Ox ---\n%!";
  Sys.catch_break true;
  try
    Lwt_main.run (Controller.start_controller ())
  with exn ->
    Printf.printf "[Ox] unexpected exception: %s\n%s\n%!"
      (Printexc.to_string exn)
      (Printexc.get_backtrace ());
    exit 1
