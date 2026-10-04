export const CAPABILITY_SCHEMA_LIMITS = Object.freeze({
  rawEvents: 100000,
  trials: 1000,
  noMidiObserved: 1000,
  signals: 8192,
  inputPorts: 128,
  outputPorts: 128,
  transitions: 10000,
  outputProbes: 1000,
  outputCleanupActions: 1000,
  cleanupErrors: 128,
  bytesPerEvent: 1024,
  refsPerTrial: 8192
});

export function validateCapabilityInventory(value) {
  if (!isPlainObject(value)) return "Inventory must be a JSON object";
  if (value.schemaVersion !== 2) return "Capability census schemaVersion must be 2";
  if (!isPlainObject(value.session)) return "session must be an object";
  if (!isPlainObject(value.totals)) return "totals must be an object";
  if (!isPlainObject(value.ports)) return "ports must be an object";

  const arrays = [
    ["ports.inputs", value.ports.inputs, CAPABILITY_SCHEMA_LIMITS.inputPorts],
    ["ports.outputs", value.ports.outputs, CAPABILITY_SCHEMA_LIMITS.outputPorts],
    ["ports.transitions", value.ports.transitions, CAPABILITY_SCHEMA_LIMITS.transitions],
    ["signals", value.signals, CAPABILITY_SCHEMA_LIMITS.signals],
    ["trials", value.trials, CAPABILITY_SCHEMA_LIMITS.trials],
    ["noMidiObserved", value.noMidiObserved, CAPABILITY_SCHEMA_LIMITS.noMidiObserved],
    ["outputProbes", value.outputProbes, CAPABILITY_SCHEMA_LIMITS.outputProbes],
    ["outputCleanupActions", value.outputCleanupActions, CAPABILITY_SCHEMA_LIMITS.outputCleanupActions],
    ["rawEvents", value.rawEvents, CAPABILITY_SCHEMA_LIMITS.rawEvents]
  ];
  for (const [name, array, maximum] of arrays) {
    if (!Array.isArray(array)) return `${name} must be an array`;
    if (array.length > maximum) return `${name} exceeds the ${maximum} item limit`;
  }

  const portRefs = new Map();
  let inputEventTotal = 0;
  for (let index = 0; index < value.ports.inputs.length; index += 1) {
    const error = validatePort(value.ports.inputs[index], index, "input", portRefs);
    if (error) return error;
    inputEventTotal += value.ports.inputs[index].events;
  }
  for (let index = 0; index < value.ports.outputs.length; index += 1) {
    const error = validatePort(value.ports.outputs[index], index, "output", portRefs);
    if (error) return error;
  }

  for (let index = 0; index < value.ports.transitions.length; index += 1) {
    const transition = value.ports.transitions[index];
    const path = `ports.transitions[${index}]`;
    if (!isPlainObject(transition)) return `${path} must be an object`;
    if (!nonNegativeFinite(transition.atMs)) return `${path}.atMs is invalid`;
    if (!shortString(transition.portRef, 80) || !portRefs.has(transition.portRef)) {
      return `${path}.portRef must reference a declared port`;
    }
    if (transition.direction !== portRefs.get(transition.portRef)) {
      return `${path}.direction must match its declared port`;
    }
    if (!shortString(transition.name, 512)) return `${path}.name is invalid`;
    if (!boundedString(transition.manufacturer, 512)) return `${path}.manufacturer is invalid`;
    if (!shortString(transition.state, 80)) return `${path}.state is invalid`;
    if (!shortString(transition.connection, 80)) return `${path}.connection is invalid`;
    if (!optionalShortString(transition.trialId, 80)) return `${path}.trialId is invalid`;
    if (!optionalShortString(transition.trialKey, 160)) return `${path}.trialKey is invalid`;
  }

  const trialsById = new Map();
  for (let index = 0; index < value.trials.length; index += 1) {
    const trial = value.trials[index];
    const path = `trials[${index}]`;
    if (!isPlainObject(trial)) return `${path} must be an object`;
    if (!shortString(trial.id, 80)) return `${path}.id is invalid`;
    if (trialsById.has(trial.id)) return `${path}.id must be unique`;
    if (!shortString(trial.planKey, 160)) return `${path}.planKey is invalid`;
    if (!shortString(trial.group, 80)) return `${path}.group is invalid`;
    if (!shortString(trial.label, 200)) return `${path}.label is invalid`;
    if (!shortString(trial.instructions, 4000)) return `${path}.instructions is invalid`;
    if (!optionalBoundedString(trial.observation, 2000)) return `${path}.observation is invalid`;
    if (!shortString(trial.result, 80)) return `${path}.result is invalid`;
    if (!nonNegativeFinite(trial.startedAtMs) || !nonNegativeFinite(trial.endedAtMs)
      || trial.endedAtMs < trial.startedAtMs) {
      return `${path} timestamps are invalid`;
    }
    if (!positiveInteger(trial.startSequence) || !nonNegativeInteger(trial.endSequence)
      || trial.endSequence < trial.startSequence - 1) {
      return `${path} sequence bounds are invalid`;
    }
    if (!nonNegativeInteger(trial.eventCount) || !nonNegativeInteger(trial.meaningfulEventCount)
      || trial.meaningfulEventCount > trial.eventCount) {
      return `${path} event counts are invalid`;
    }
    const sequenceEventCount = Math.max(0, trial.endSequence - trial.startSequence + 1);
    if (trial.eventCount !== sequenceEventCount) return `${path}.eventCount does not match its sequence bounds`;
    const portError = validateStringArray(trial.portRefs, `${path}.portRefs`, CAPABILITY_SCHEMA_LIMITS.inputPorts, 80);
    if (portError) return portError;
    if (trial.portRefs.some((ref) => portRefs.get(ref) !== "input")) {
      return `${path}.portRefs must reference declared input ports`;
    }
    const signalError = validateStringArray(
      trial.signalRefs,
      `${path}.signalRefs`,
      CAPABILITY_SCHEMA_LIMITS.refsPerTrial,
      320
    );
    if (signalError) return signalError;
    trialsById.set(trial.id, trial);
  }

  for (let index = 0; index < value.ports.transitions.length; index += 1) {
    const transition = value.ports.transitions[index];
    const path = `ports.transitions[${index}]`;
    if (transition.trialId !== null && transition.trialId !== undefined) {
      if (!trialsById.has(transition.trialId)) {
        return `${path}.trialId must reference a declared trial`;
      }
      if (transition.trialKey !== trialsById.get(transition.trialId).planKey) {
        return `${path}.trialKey must match its trial`;
      }
    } else if (transition.trialKey !== null && transition.trialKey !== undefined) {
      return `${path}.trialKey requires a trialId`;
    }
  }

  const noMidiTrialIds = new Set();
  for (let index = 0; index < value.noMidiObserved.length; index += 1) {
    const observation = value.noMidiObserved[index];
    const path = `noMidiObserved[${index}]`;
    if (!isPlainObject(observation)) return `${path} must be an object`;
    if (!shortString(observation.trialId, 80) || !trialsById.has(observation.trialId)) {
      return `${path}.trialId must reference a declared trial`;
    }
    if (noMidiTrialIds.has(observation.trialId)) return `${path}.trialId must be unique`;
    const trial = trialsById.get(observation.trialId);
    if (trial.result !== "no-midi-observed" || observation.result !== "no-midi-observed") {
      return `${path}.result must match a no-midi-observed trial`;
    }
    if (observation.planKey !== trial.planKey) return `${path}.planKey must match its trial`;
    if (observation.label !== trial.label) return `${path}.label must match its trial`;
    if (!optionalBoundedString(observation.observation, 2000)) return `${path}.observation is invalid`;
    if (!nonNegativeFinite(observation.recordedAtMs)) return `${path}.recordedAtMs is invalid`;
    noMidiTrialIds.add(observation.trialId);
  }
  for (const trial of trialsById.values()) {
    if (trial.result === "no-midi-observed" && !noMidiTrialIds.has(trial.id)) {
      return `trial ${trial.id} is missing its noMidiObserved entry`;
    }
  }

  const outputProbeIds = new Set();
  for (let index = 0; index < value.outputProbes.length; index += 1) {
    const error = validateOutputProbe(value.outputProbes[index], index, portRefs, outputProbeIds);
    if (error) return error;
  }

  for (let index = 0; index < value.outputCleanupActions.length; index += 1) {
    const error = validateOutputCleanup(value.outputCleanupActions[index], index, portRefs);
    if (error) return error;
  }

  let previousSequence = 0;
  for (let index = 0; index < value.rawEvents.length; index += 1) {
    const event = value.rawEvents[index];
    const path = `rawEvents[${index}]`;
    if (!isPlainObject(event)) return `${path} must be an object`;
    if (!Number.isInteger(event.sequence) || event.sequence <= previousSequence) {
      return `${path}.sequence must be a strictly increasing positive integer`;
    }
    previousSequence = event.sequence;
    if (!shortString(event.portRef, 80) || portRefs.get(event.portRef) !== "input") {
      return `${path}.portRef must reference a declared input port`;
    }
    if (!Array.isArray(event.bytes) || event.bytes.length === 0 || event.bytes.length > CAPABILITY_SCHEMA_LIMITS.bytesPerEvent) {
      return `${path}.bytes is invalid`;
    }
    if (!event.bytes.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 255)) {
      return `${path}.bytes must contain MIDI bytes`;
    }
    if (!isPlainObject(event.parsed) || !shortString(event.parsed.messageType, 80) || !shortString(event.parsed.signalKey, 160)) {
      return `${path}.parsed is invalid`;
    }
    if (!finiteNumber(event.eventTimestampMs) || !finiteNumber(event.receivedAtMs)
      || !finiteNumber(event.callbackDelayMs)) {
      return `${path} timestamps are invalid`;
    }
    if (!optionalShortString(event.mirrorCandidateId, 80)) return `${path}.mirrorCandidateId is invalid`;
    if (event.trialId !== null && event.trialId !== undefined) {
      if (!shortString(event.trialId, 80) || !trialsById.has(event.trialId)) {
        return `${path}.trialId must reference a declared trial`;
      }
      if (event.trialKey !== trialsById.get(event.trialId).planKey) {
        return `${path}.trialKey must match its trial`;
      }
    } else if (event.trialKey !== null && event.trialKey !== undefined) {
      return `${path}.trialKey requires a trialId`;
    }
  }

  return validateTotals(value, inputEventTotal);
}

function validatePort(port, index, expectedDirection, portRefs) {
  const collection = expectedDirection === "input" ? "ports.inputs" : "ports.outputs";
  const path = `${collection}[${index}]`;
  if (!isPlainObject(port)) return `${path} must be an object`;
  if (!shortString(port.ref, 80)) return `${path}.ref is invalid`;
  if (portRefs.has(port.ref)) return `${path}.ref must be unique across all ports`;
  if (!shortString(port.id, 2048)) return `${path}.id is invalid`;
  if (port.direction !== expectedDirection) return `${path}.direction must be ${expectedDirection}`;
  if (!shortString(port.name, 512)) return `${path}.name is invalid`;
  if (!boundedString(port.manufacturer, 512)) return `${path}.manufacturer is invalid`;
  if (!shortString(port.state, 80)) return `${path}.state is invalid`;
  if (!shortString(port.connection, 80)) return `${path}.connection is invalid`;
  if (typeof port.present !== "boolean") return `${path}.present must be boolean`;
  if (!optionalBoundedString(port.openError, 2000)) return `${path}.openError is invalid`;
  if (!nonNegativeFinite(port.firstSeenAtMs)) return `${path}.firstSeenAtMs is invalid`;
  if (expectedDirection === "input") {
    for (const field of ["events", "notes", "controls", "other", "possibleMirrors"]) {
      if (!nonNegativeInteger(port[field])) return `${path}.${field} must be a non-negative integer`;
    }
    if (port.notes + port.controls + port.other !== port.events) {
      return `${path} message category counts must equal events`;
    }
  } else if (!nonNegativeInteger(port.messagesSent)) {
    return `${path}.messagesSent must be a non-negative integer`;
  }
  portRefs.set(port.ref, expectedDirection);
  return null;
}

function validateOutputProbe(probe, index, portRefs, ids) {
  const path = `outputProbes[${index}]`;
  if (!isPlainObject(probe)) return `${path} must be an object`;
  if (!shortString(probe.id, 80)) return `${path}.id is invalid`;
  if (ids.has(probe.id)) return `${path}.id must be unique`;
  if (!shortString(probe.outputRef, 80) || portRefs.get(probe.outputRef) !== "output") {
    return `${path}.outputRef must reference a declared output port`;
  }
  if (!integerInRange(probe.channel, 1, 16)) return `${path}.channel is invalid`;
  if (!integerInRange(probe.note, 0, 127)) return `${path}.note is invalid`;
  if (!integerInRange(probe.velocity, 1, 32)) return `${path}.velocity exceeds the safe probe range`;
  if (!nonNegativeFinite(probe.sentAtMs)) return `${path}.sentAtMs is invalid`;
  if (!integerInRange(probe.noteLengthMs, 1, 2000)) return `${path}.noteLengthMs is invalid`;
  if (!shortString(probe.result, 80)) return `${path}.result is invalid`;
  if (!boundedString(probe.notes, 1000)) return `${path}.notes is invalid`;
  for (const field of ["noteOnSent", "noteOffSent", "allNotesOffSent", "allSoundOffSent", "cleanupComplete"]) {
    if (typeof probe[field] !== "boolean") return `${path}.${field} must be boolean`;
  }
  if (!nonNegativeInteger(probe.messagesSent)) return `${path}.messagesSent must be a non-negative integer`;
  const expectedMessages = [probe.noteOnSent, probe.noteOffSent, probe.allNotesOffSent, probe.allSoundOffSent]
    .filter(Boolean).length;
  if (probe.messagesSent !== expectedMessages) return `${path}.messagesSent does not match its send flags`;
  const expectedCleanup = probe.noteOffSent && probe.allNotesOffSent && probe.allSoundOffSent;
  if (probe.cleanupComplete !== expectedCleanup) return `${path}.cleanupComplete does not match its cleanup flags`;
  if (!optionalBoundedString(probe.sendError, 2000)) return `${path}.sendError is invalid`;
  if (!optionalBoundedString(probe.cleanupError, 4000)) return `${path}.cleanupError is invalid`;
  if (probe.outputClosed !== undefined && typeof probe.outputClosed !== "boolean") {
    return `${path}.outputClosed must be boolean`;
  }
  if (!optionalBoundedString(probe.closeError, 2000)) return `${path}.closeError is invalid`;
  if (probe.observedAtMs !== undefined && probe.observedAtMs !== null && !nonNegativeFinite(probe.observedAtMs)) {
    return `${path}.observedAtMs is invalid`;
  }
  ids.add(probe.id);
  return null;
}

function validateOutputCleanup(action, index, portRefs) {
  const path = `outputCleanupActions[${index}]`;
  if (!isPlainObject(action)) return `${path} must be an object`;
  if (!nonNegativeFinite(action.atMs)) return `${path}.atMs is invalid`;
  if (!shortString(action.reason, 200)) return `${path}.reason is invalid`;
  if (!shortString(action.outputRef, 80) || portRefs.get(action.outputRef) !== "output") {
    return `${path}.outputRef must reference a declared output port`;
  }
  if (typeof action.clearCalled !== "boolean") return `${path}.clearCalled must be boolean`;
  for (const field of ["noteOffsSent", "allNotesOffSent", "allSoundOffSent", "messagesSent"]) {
    if (!nonNegativeInteger(action[field])) return `${path}.${field} must be a non-negative integer`;
  }
  const expectedMessages = action.noteOffsSent + action.allNotesOffSent + action.allSoundOffSent;
  if (action.messagesSent !== expectedMessages) return `${path}.messagesSent does not match its cleanup counts`;
  const errorsError = validateStringArray(
    action.errors,
    `${path}.errors`,
    CAPABILITY_SCHEMA_LIMITS.cleanupErrors,
    2000,
    false
  );
  if (errorsError) return errorsError;
  if (action.outputClosed !== undefined && typeof action.outputClosed !== "boolean") {
    return `${path}.outputClosed must be boolean`;
  }
  if (!optionalBoundedString(action.closeError, 2000)) return `${path}.closeError is invalid`;
  return null;
}

function validateTotals(value, inputEventTotal) {
  const { session, totals } = value;
  if (!positiveInteger(session.rawEventLimit) || session.rawEventLimit > CAPABILITY_SCHEMA_LIMITS.rawEvents) {
    return "session.rawEventLimit is invalid";
  }
  if (!nonNegativeInteger(session.rawEventsDropped)) return "session.rawEventsDropped is invalid";
  if (!nonNegativeInteger(totals.events)) return "totals.events is invalid";
  if (!nonNegativeInteger(totals.rawEventsRetained)) return "totals.rawEventsRetained is invalid";
  if (!nonNegativeInteger(totals.rawEventsDropped)) return "totals.rawEventsDropped is invalid";
  for (const field of ["distinctSignals", "possibleMirrorCandidates", "trials", "noMidiObserved", "outputProbes"]) {
    if (!nonNegativeInteger(totals[field])) return `totals.${field} is invalid`;
  }
  if (totals.rawEventsRetained !== value.rawEvents.length) {
    return "totals.rawEventsRetained must equal rawEvents.length";
  }
  if (totals.rawEventsDropped !== session.rawEventsDropped) {
    return "totals.rawEventsDropped must equal session.rawEventsDropped";
  }
  if (totals.events !== totals.rawEventsRetained + totals.rawEventsDropped) {
    return "totals.events must equal retained plus dropped raw events";
  }
  if (totals.events !== inputEventTotal) return "totals.events must equal the input-port event total";
  if (totals.distinctSignals !== value.signals.length) return "totals.distinctSignals must equal signals.length";
  if (totals.trials !== value.trials.length) return "totals.trials must equal trials.length";
  if (totals.noMidiObserved !== value.noMidiObserved.length) {
    return "totals.noMidiObserved must equal noMidiObserved.length";
  }
  if (totals.outputProbes !== value.outputProbes.length) {
    return "totals.outputProbes must equal outputProbes.length";
  }
  if (value.rawEvents.length > session.rawEventLimit) return "rawEvents exceeds session.rawEventLimit";
  if (session.rawEventsDropped > 0 && value.rawEvents.length !== session.rawEventLimit) {
    return "dropped raw events require a full retained raw-event buffer";
  }
  return null;
}

function validateStringArray(value, path, maximumItems, maximumLength, requireUnique = true) {
  if (!Array.isArray(value)) return `${path} must be an array`;
  if (value.length > maximumItems) return `${path} exceeds the ${maximumItems} item limit`;
  if (!value.every((item) => shortString(item, maximumLength))) return `${path} contains an invalid string`;
  if (requireUnique && new Set(value).size !== value.length) return `${path} must not contain duplicates`;
  return null;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function shortString(value, maximumLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maximumLength;
}

function boundedString(value, maximumLength) {
  return typeof value === "string" && value.length <= maximumLength;
}

function optionalShortString(value, maximumLength) {
  return value === undefined || value === null || shortString(value, maximumLength);
}

function optionalBoundedString(value, maximumLength) {
  return value === undefined || value === null || boundedString(value, maximumLength);
}

function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function nonNegativeFinite(value) {
  return finiteNumber(value) && value >= 0;
}

function nonNegativeInteger(value) {
  return Number.isInteger(value) && value >= 0;
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

function integerInRange(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}
