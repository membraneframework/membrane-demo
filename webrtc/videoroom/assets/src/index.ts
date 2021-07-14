import { Room } from "./room";

let room = new Room();
room.init().then(() => room.join());
