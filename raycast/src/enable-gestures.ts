import { send } from "./mouseline";

export default async function Command() {
  await send("enable");
}
