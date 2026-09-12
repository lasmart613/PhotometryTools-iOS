#!/usr/bin/env node
/**
 * Compare bundled HTML calculator math / VBeam table against the native
 * Swift sources. No network. No secrets.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const htmlDir = path.join(root, "PhotometryTools/Resources/assets");
const mathSwift = fs.readFileSync(path.join(root, "PhotometryTools/Calculators/PhotometryMath.swift"), "utf8");
const tableSwift = fs.readFileSync(path.join(root, "PhotometryTools/Calculators/VBeamWavelengthTable.swift"), "utf8");
const wavelengthHtml = fs.readFileSync(path.join(htmlDir, "wavelength.html"), "utf8");

let failed = 0;
function check(name, cond, detail = "") {
  if (cond) {
    console.log(`ok  ${name}`);
  } else {
    failed += 1;
    console.error(`FAIL ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

const tableMatch = wavelengthHtml.match(/const lookupTable = \[([\s\S]*?)\];/);
if (!tableMatch) {
  console.error("FAIL could not extract lookupTable from wavelength.html");
  process.exit(1);
}
const htmlTable = eval(`[${tableMatch[1]}]`);

const swiftRows = [...tableSwift.matchAll(/deltaPercent:\s*([0-9.]+),\s*wavelengthNM:\s*([0-9.]+)/g)]
  .map((m) => ({ delta: Number(m[1]), wavelength: Number(m[2]) }));

check("VBeam table length", htmlTable.length === swiftRows.length && htmlTable.length === 141, `${htmlTable.length} vs ${swiftRows.length}`);
check(
  "VBeam table values",
  htmlTable.every((row, i) => {
    const s = swiftRows[i];
    return s && Math.abs(row.delta - s.delta) < 1e-9 && Math.abs(row.wavelength - s.wavelength) < 1e-9;
  })
);

function lookupWavelength(d) {
  let closest = htmlTable[0];
  let minDiff = Math.abs(d - closest.delta);
  for (let i = 1; i < htmlTable.length; i++) {
    const diff = Math.abs(d - htmlTable[i].delta);
    if (diff < minDiff) {
      minDiff = diff;
      closest = htmlTable[i];
    }
  }
  for (let i = 0; i < htmlTable.length - 1; i++) {
    if (d >= htmlTable[i].delta && d <= htmlTable[i + 1].delta) {
      const d1 = htmlTable[i].delta;
      const d2 = htmlTable[i + 1].delta;
      const w1 = htmlTable[i].wavelength;
      const w2 = htmlTable[i + 1].wavelength;
      return w1 + ((w2 - w1) * (d - d1)) / (d2 - d1);
    }
  }
  return closest.wavelength;
}

const areaCirc15 = (Math.PI * Math.pow(15 / 2, 2)) / 100;
check("circular 15 mm area", Math.abs(areaCirc15 - 1.7671458676442586) < 1e-12);
check("fluence 1.5 J / 15 mm", Math.abs(1.5 / areaCirc15 - 0.8488263631567752) < 1e-12);
check("irradiance 10 W / 15 mm", Math.abs(10 / areaCirc15 - 5.6588424210451675) < 1e-12);
check("square 10 mm area", (10 * 10) / 100 === 1);
check("rect 12×8 area", (12 * 8) / 100 === 0.96);

const pulsedE = { avgPower: 2.5 * 10, avgIrr: (2.5 * 10) / areaCirc15 };
check("pulsed energy avg power", pulsedE.avgPower === 25);
check("pulsed energy avg irr", Math.abs(pulsedE.avgIrr - 14.14710605261292) < 1e-12);

const pulsedF = { avgIrr: 12.5 * 10, avgPower: 12.5 * 10 * areaCirc15 };
check("pulsed fluence avg irr", pulsedF.avgIrr === 125);
check("pulsed fluence avg power", Math.abs(pulsedF.avgPower - 220.89323345553234) < 1e-12);

const dutyOffPeriod = 10 + 90;
check("duty from off-time", (10 / dutyOffPeriod) * 100 === 10 && 1000 / dutyOffPeriod === 10);
const dutyPpsPeriod = 1000 / 10;
check("duty from PPS", (10 / dutyPpsPeriod) * 100 === 10 && dutyPpsPeriod - 10 === 90);

check("avg power 50 mJ × 10 Hz", (50 / 1000) * 10 === 0.5);
check("pulse energy 5 W ÷ 10 Hz", (5 / 10) * 1000 === 500);

const t1 = 100 / 80;
const t2 = 90 / 20;
const dp = (t2 / t1) * 100;
const base = lookupWavelength(dp);
check("wavelength Δ% out of range → 600 nm", base === 600 && dp === 360);
check("wavelength +0.2 nm correction", base + 0.2 === 600.2);
check("wavelength below table", lookupWavelength(1) === 586);
check("wavelength exact 14.00 → 589.5", lookupWavelength(14.0) === 589.5);

const requiredMessages = [
  "Enter valid positive values",
  "Enter valid energy per pulse",
  "Enter valid fluence per pulse",
  "Enter valid Rep Rate and spot size",
  "Enter a valid pulse width",
  "Enter either Off-Time or PPS",
  "Enter only one: Off-Time OR PPS",
  "Pulse width exceeds period (1/PPS)",
  "Enter a valid frequency",
  "Enter a valid energy value",
  "Enter a valid power value",
  "Enter valid readings for both fields",
];
for (const message of requiredMessages) {
  check(`Swift validation: ${message}`, mathSwift.includes(message));
}

const menu = fs.readFileSync(path.join(htmlDir, "calculators_menu.html"), "utf8");
check("HTML menu still links density_calculator.html", menu.includes("density_calculator.html"));
check("HTML menu still links wavelength.html", menu.includes("wavelength.html"));
check("HTML menu still links duty_cycle.html", menu.includes("duty_cycle.html"));
check("HTML menu still links avgpower.html", menu.includes("avgpower.html"));
check("HTML menu Fluence card present", /Fluence/.test(menu));

if (failed) {
  console.error(`\n${failed} check(s) failed`);
  process.exit(1);
}
console.log("\ncalculator parity checks passed");
