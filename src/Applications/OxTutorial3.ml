module MyApplication : Ox_Controller.OXMODULE = struct
  open Ox_Controller.OxPlatform
  open OpenFlow0x01
  type xid = Message.xid

  (* TODO(arjun): provide in library? *)
  let add_flow prio pat actions = 
    let open FlowMod in
    { mod_cmd = Command.AddFlow;
      match_ = pat;
      priority = prio;
      actions = actions;
      cookie = 0L;
      idle_timeout = Timeout.Permanent;
      hard_timeout = Timeout.Permanent;
      notify_when_removed = false;
      out_port =  None;
      apply_to_packet = None;
      check_overlap = false
    }

  (* TODO(arjun): decide where this goes. matchArp is trivial, but we will
     later ask them to calculate a cross product. *)
  let match_arp = 
    let open Match in
    { dlSrc = None; dlDst = None; dlTyp = Some 0x806; dlVlan = None;
      dlVlanPcp = None; nwSrc = None; nwDst = None; nwProto = None;
      nwTos = None; tpSrc = None; tpDst = None; inPort = None }

  (* FILL: configure the flow table to efficiently implement the packet
     processing function you've written in packet_in *)
  let switch_connected (sw : switchId) : unit =
    Printf.printf "Switch %Ld connected.\n%!" sw;
    send_flow_mod sw 0l
      (add_flow 200 match_arp []);
    send_flow_mod sw 1l
      (add_flow 199 Match.all [Action.Output PseudoPort.AllPorts])
      
  let switch_disconnected (sw : switchId) : unit =
    Printf.printf "Switch %Ld disconnected.\n%!" sw

  (* FILL: Use exactly the same packet_in function you wrote from
     OxTutorial1.  *)
  let packet_in (sw : switchId) (xid : xid) (pktIn : PacketIn.t) : unit =
    Printf.printf "Received a PacketIn message from switch %Ld:\n%s\n%!"
      sw (PacketIn.to_string pktIn);
    let payload = pktIn.PacketIn.payload in
    let pk = Payload.parse payload in
    if pk.Packet.dlTyp = 0x806 then
      send_packet_out sw 0l
        { PacketOut.payload = payload;
          PacketOut.port_id = None;
          PacketOut.actions = []
        }
    else 
      send_packet_out sw 0l
        { PacketOut.payload = payload;
          PacketOut.port_id = None;
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
