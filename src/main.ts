import { mount } from "svelte";
import App from "./App.svelte";

const mountTarget = document.getElementById("app");

if (!mountTarget) {
  throw new Error('mount target "#app" is missing in index.html');
}

export default mount(App, { target: mountTarget });
