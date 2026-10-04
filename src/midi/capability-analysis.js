import { parseMidiMessage } from "./midi-parser.js";

const DEFAULT_OPTIONS = Object.freeze({
  mirrorWindowMs: 12,
  mirrorMatchThreshold: 0.95,
  mirrorMinimumMatches: 20,
  mirrorMinimumSignatures: 3
});

const MISSING_PORT = "(missing port)";
const UNASSIGNED_TRIAL = "(unassigned)";
const PARSED_FIELD_NAMES = Object.freeze([
  "category",
  "messageType",
  "phase",
  "channel",
  "number",
  "value",
  "velocity",
  "signalKey"
]);

/**
 * Analyze a schema-v2 MIDI inventory without altering or deduplicating its raw
 * events. Every conclusion in the returned object can therefore be traced back
 * to the original capture.
 */
export function analyzeMidiCapabilities(inventory, options = {}) {
  const source = isPlainObject(inventory) ? inventory : {};
  const settings = normalizeOptions(options);
  const rawEvents = Array.isArray(source.rawEvents) ? source.rawEvents : [];
  const events = rawEvents.map(normalizeEvent).sort(compareEvents);
  const sessionSummary = normalizeSession(source.session);
  const trials = normalizeTrials(source.trials);
  const noMidiObservations = normalizeNoMidiObservations(source.noMidiObserved);
  const outputProbeSummaries = normalizeOutputProbes(source.outputProbes);
  const outputCleanupActions = normalizeOutputCleanupActions(source.outputCleanupActions);
  const ports = normalizePorts(source.ports);
  const portTransitions = correlatePortTransitions(source.ports?.transitions, trials);
  ports.transitions = portTransitions;
  const parseDiagnostics = summarizeParseDiagnostics(events);

  const portSummaries = buildPortSummaries(events, ports);
  const messageSummaries = summarizeGroups(events, (event) => [
    event.portRef,
    event.parsed.messageType || "unknown"
  ], ([portRef, messageType], groupedEvents) => ({
    portRef,
    messageType,
    categories: uniqueStrings(groupedEvents.map((event) => event.parsed.category))
  }));
  const signalSummaries = summarizeGroups(events, (event) => [
    event.portRef,
    event.parsed.signalKey || fallbackSignalKey(event.parsed)
  ], ([portRef, signalKey], groupedEvents) => ({
    portRef,
    signalKey,
    categories: uniqueStrings(groupedEvents.map((event) => event.parsed.category)),
    messageTypes: uniqueStrings(groupedEvents.map((event) => event.parsed.messageType)),
    channels: uniqueNumbers(groupedEvents.map((event) => event.parsed.channel)),
    numbers: uniqueNumbers(groupedEvents.map((event) => event.parsed.number)),
    attackVelocitySummary: summarizeSelectedValues(
      groupedEvents,
      (event) => isNoteOn(event.parsed),
      (event) => event.parsed.velocity ?? event.parsed.value
    ),
    releaseVelocitySummary: summarizeSelectedValues(
      groupedEvents,
      (event) => isNoteOff(event.parsed),
      (event) => event.parsed.velocity ?? event.parsed.value
    )
  }));
  const trialSummaries = buildTrialSummaries(events, trials, noMidiObservations);
  const noteSummary = analyzeNotes(events);
  const mirrorPairs = analyzeMirrorPairs(events, settings);
  const mirrorCandidates = mirrorPairs.filter((pair) => pair.isCandidate);

  return {
    analysisSchemaVersion: 1,
    inventorySchemaVersion: source.schemaVersion ?? null,
    options: settings,
    eventCount: events.length,
    sessionSummary,
    ports,
    trials,
    noMidiObservations,
    outputProbeSummaries,
    outputCleanupActions,
    portTransitions,
    parseDiagnostics,
    portSummaries,
    messageSummaries,
    signalSummaries,
    trialSummaries,
    noteSummary,
    mirrorPairs,
    mirrorCandidates,
    limitations: buildLimitations(source, rawEvents, events, ports, {
      parseDiagnostics,
      outputProbeSummaries,
      outputCleanupActions
    })
  };
}

// A descriptive alias for callers that treat an inventory as the primary unit.
export const analyzeCapabilityInventory = analyzeMidiCapabilities;

export function summarizeNumericValues(values, segmentKeys = null) {
  const entries = values.map((value, index) => ({
    value: isFiniteNumber(value) ? Number(value) : null,
    segmentKey: Array.isArray(segmentKeys) ? segmentKeys[index] : "all"
  }));
  const numbers = entries.filter((entry) => entry.value !== null).map((entry) => entry.value);
  if (numbers.length === 0) {
    return {
      count: 0,
      missingCount: values.length,
      min: null,
      max: null,
      range: null,
      mean: null,
      median: null,
      distinctCount: 0,
      distinctValues: [],
      stepSummary: emptyStepSummary()
    };
  }

  const sorted = [...numbers].sort((a, b) => a - b);
  const distinctValues = [...new Set(sorted)];
  const adjacentDistinctSteps = [];
  for (let index = 1; index < distinctValues.length; index += 1) {
    adjacentDistinctSteps.push(roundNumber(distinctValues[index] - distinctValues[index - 1]));
  }

  const transitions = [];
  for (let index = 1; index < entries.length; index += 1) {
    const previous = entries[index - 1];
    const current = entries[index];
    if (previous.value === null || current.value === null || previous.segmentKey !== current.segmentKey) continue;
    transitions.push(roundNumber(current.value - previous.value));
  }
  const changedTransitions = transitions.filter((step) => step !== 0);
  const absoluteTransitions = changedTransitions.map(Math.abs);

  return {
    count: numbers.length,
    missingCount: values.length - numbers.length,
    min: sorted[0],
    max: sorted.at(-1),
    range: roundNumber(sorted.at(-1) - sorted[0]),
    mean: roundNumber(numbers.reduce((sum, value) => sum + value, 0) / numbers.length),
    median: quantile(sorted, 0.5),
    distinctCount: distinctValues.length,
    distinctValues,
    stepSummary: {
      adjacentDistinctSteps,
      smallestObservedStep: adjacentDistinctSteps.length > 0 ? Math.min(...adjacentDistinctSteps) : null,
      largestObservedStep: adjacentDistinctSteps.length > 0 ? Math.max(...adjacentDistinctSteps) : null,
      transitionCount: transitions.length,
      zeroTransitionCount: transitions.filter((step) => step === 0).length,
      changedTransitionCount: changedTransitions.length,
      smallestAbsoluteTransition: absoluteTransitions.length > 0 ? Math.min(...absoluteTransitions) : null,
      largestAbsoluteTransition: absoluteTransitions.length > 0 ? Math.max(...absoluteTransitions) : null,
      medianAbsoluteTransition: absoluteTransitions.length > 0
        ? quantile([...absoluteTransitions].sort((a, b) => a - b), 0.5)
        : null,
      modalAbsoluteTransition: mode(absoluteTransitions),
      distinctSignedTransitions: [...new Set(changedTransitions)].sort((a, b) => a - b)
    }
  };
}

export function formatCapabilityReportMarkdown(analysis) {
  const lines = [
    "# MIDI capability analysis",
    "",
    "This report summarizes observed data only. The source path is intentionally omitted.",
    "",
    "## Overview",
    "",
    "| Item | Value |",
    "| --- | ---: |",
    `| Inventory schema | ${cell(analysis.inventorySchemaVersion ?? "unknown")} |`,
    `| Raw events | ${numberCell(analysis.eventCount)} |`,
    `| Declared inputs | ${numberCell(analysis.ports?.inputs?.length ?? 0)} |`,
    `| Declared outputs | ${numberCell(analysis.ports?.outputs?.length ?? 0)} |`,
    `| Declared trials | ${numberCell(analysis.trials?.length ?? 0)} |`,
    `| Explicit no-MIDI observations | ${numberCell(analysis.noMidiObservations?.length ?? 0)} |`,
    `| Output probes | ${numberCell(analysis.outputProbeSummaries?.length ?? 0)} |`,
    `| Output cleanup actions | ${numberCell(analysis.outputCleanupActions?.length ?? 0)} |`,
    `| Port transitions | ${numberCell(analysis.portTransitions?.length ?? 0)} |`,
    `| Parsed-field mismatch events | ${numberCell(analysis.parseDiagnostics?.mismatchEventCount ?? 0)} |`,
    `| Mirror window | ${numberCell(analysis.options?.mirrorWindowMs)} ms |`,
    `| Mirror candidates | ${numberCell(analysis.mirrorCandidates?.length ?? 0)} |`,
    ""
  ];

  lines.push("## Session and GLOBE metadata", "");
  appendTable(lines, ["Field", "Value"], sessionMetadataRows(analysis.sessionSummary));

  lines.push("## Declared ports", "");
  appendTable(lines,
    ["Direction", "Port reference", "Name", "Manufacturer"],
    [...(analysis.ports?.inputs ?? []), ...(analysis.ports?.outputs ?? [])].map((port) => [
      port.direction,
      port.portRef,
      port.name || "-",
      port.manufacturer || "-"
    ]));

  lines.push("## Per-port summary", "");
  appendTable(lines,
    ["Direction", "Port", "Events", "Messages", "Signals", "Trials", "Delay p50 / p95 ms"],
    (analysis.portSummaries ?? []).map((summary) => [
      summary.direction,
      summary.portRef,
      summary.eventCount,
      summary.messageTypes.join(", ") || "-",
      summary.signalCount,
      summary.trialCount,
      formatPair(summary.callbackDelaySummary.median, summary.callbackDelaySummary.p95)
    ]));

  lines.push("## Per-message summary", "");
  appendTable(lines,
    ["Port", "Message", "Events", "Min", "Max", "Distinct", "Smallest step"],
    (analysis.messageSummaries ?? []).map((summary) => [
      summary.portRef,
      summary.messageType,
      summary.eventCount,
      summary.valueSummary.min,
      summary.valueSummary.max,
      summary.valueSummary.distinctCount,
      summary.valueSummary.stepSummary.smallestObservedStep
    ]));

  lines.push("## Per-signal summary", "");
  appendTable(lines,
    ["Port", "Signal", "Messages", "Events", "Range", "Distinct", "Smallest step"],
    (analysis.signalSummaries ?? []).map((summary) => [
      summary.portRef,
      summary.signalKey,
      summary.messageTypes.join(", ") || "-",
      summary.eventCount,
      formatRange(summary.valueSummary),
      summary.valueSummary.distinctCount,
      summary.valueSummary.stepSummary.smallestObservedStep
    ]));

  lines.push("## Trials and observations", "");
  appendTable(lines,
    ["Trial ID", "Trial key", "Label", "Status", "Events observed / declared", "Meaningful", "Ports", "Observation", "Explicit no MIDI"],
    (analysis.trialSummaries ?? []).map((summary) => [
      summary.trialId,
      summary.trialKey || "-",
      summary.label || "-",
      summary.status || "-",
      `${summary.eventCount} / ${summary.declaredEventCount ?? "unknown"}`,
      summary.declaredMeaningfulEventCount,
      summary.portRefs.join(", ") || "-",
      summary.observation || "-",
      summary.noMidiObserved ? "yes" : "no"
    ]));

  lines.push("## Explicit no-MIDI observations", "");
  appendTable(lines,
    ["Trial ID", "Trial key", "Label", "Result", "Recorded at ms", "Observation"],
    (analysis.noMidiObservations ?? []).map((observation) => [
      observation.trialId || "-",
      observation.trialKey || "-",
      observation.label || "-",
      observation.result || "no-midi-observed",
      observation.recordedAtMs,
      observation.observation || "-"
    ]));

  lines.push("## Port transitions and trial correlation", "");
  appendTable(lines,
    ["At ms", "Port", "Direction", "State / connection", "Name", "Correlated trial", "Correlation"],
    (analysis.portTransitions ?? []).map((transition) => [
      transition.atMs,
      transition.portRef,
      transition.direction || "-",
      [transition.state, transition.connection].filter(Boolean).join(" / ") || "-",
      transition.name || "-",
      transition.correlatedTrialLabel || transition.correlatedTrialKey || transition.correlatedTrialId || "outside a recorded trial",
      transition.trialCorrelation || "none"
    ]));

  lines.push("## Output probes", "");
  appendTable(lines,
    ["Probe", "Output", "Channel / note / velocity", "Result", "Observation", "Note on/off", "All notes/sound off", "Messages", "Cleanup", "Port close", "Errors"],
    (analysis.outputProbeSummaries ?? []).map((probe) => [
      probe.id,
      probe.outputRef,
      formatProbeMessage(probe),
      probe.result || "-",
      probe.observation || "-",
      `${booleanWord(probe.noteOnSent)} / ${booleanWord(probe.noteOffSent)}`,
      `${booleanWord(probe.allNotesOffSent)} / ${booleanWord(probe.allSoundOffSent)}`,
      probe.messagesSent,
      probe.cleanupStatus,
      probe.outputCloseStatus,
      [probe.sendError, probe.cleanupError, probe.closeError].filter(Boolean).join("; ") || "-"
    ]));

  lines.push("## Output cleanup actions", "");
  appendTable(lines,
    ["At ms", "Output", "Reason", "Messages", "Clear", "Note offs", "All notes off", "All sound off", "Status", "Errors"],
    (analysis.outputCleanupActions ?? []).map((action) => [
      action.atMs,
      action.outputRef,
      action.reason || "-",
      action.messagesSent,
      booleanWord(action.clearCalled),
      action.noteOffsSent,
      action.allNotesOffSent,
      action.allSoundOffSent,
      action.cleanupStatus,
      action.errors.join("; ") || "-"
    ]));

  lines.push("## Raw-byte decode verification", "");
  appendTable(lines,
    ["Field", "Count"],
    parseDiagnosticRows(analysis.parseDiagnostics));

  lines.push("## Note integrity and polyphony", "");
  appendTable(lines,
    ["Port", "On", "Off", "Pairs", "Unmatched on", "Unmatched off", "Max concurrent", "Duration p50 ms"],
    (analysis.noteSummary?.perPort ?? []).map((summary) => [
      summary.portRef,
      summary.noteOnCount,
      summary.noteOffCount,
      summary.pairedCount,
      summary.unmatchedNoteOnCount,
      summary.unmatchedNoteOffCount,
      summary.maxConcurrentNotes,
      summary.durationSummary.median
    ]));

  lines.push("## Mirror-pair evidence", "");
  appendTable(lines,
    ["Port A", "Port B", "Comparable A/B", "Matched", "Signatures", "A/B rates", "Strict rate", "Median skew ms", "Median absolute skew ms", "Candidate"],
    (analysis.mirrorPairs ?? []).map((pair) => [
      pair.portA,
      pair.portB,
      `${pair.comparableEventCountA}/${pair.comparableEventCountB}`,
      pair.matchedCount,
      pair.matchedSignatureCount,
      `${formatPercent(pair.matchRateA)} / ${formatPercent(pair.matchRateB)}`,
      formatPercent(pair.strictMatchRate),
      pair.skewSummary.median,
      pair.absoluteSkewSummary.median,
      pair.isCandidate ? "yes" : "no"
    ]));

  lines.push("## Limitations", "");
  for (const limitation of analysis.limitations ?? []) {
    lines.push(`- ${inlineText(limitation)}`);
  }
  lines.push("");
  return `${lines.join("\n").trimEnd()}\n`;
}

export const renderCapabilityMarkdown = formatCapabilityReportMarkdown;

function normalizeOptions(options) {
  const mirrorWindowMs = finiteOr(options.mirrorWindowMs, DEFAULT_OPTIONS.mirrorWindowMs);
  const mirrorMatchThreshold = finiteOr(options.mirrorMatchThreshold, DEFAULT_OPTIONS.mirrorMatchThreshold);
  const mirrorMinimumMatches = finiteOr(options.mirrorMinimumMatches, DEFAULT_OPTIONS.mirrorMinimumMatches);
  const mirrorMinimumSignatures = finiteOr(options.mirrorMinimumSignatures, DEFAULT_OPTIONS.mirrorMinimumSignatures);
  if (mirrorWindowMs < 0) throw new RangeError("mirrorWindowMs must be non-negative");
  if (mirrorMatchThreshold < 0 || mirrorMatchThreshold > 1) {
    throw new RangeError("mirrorMatchThreshold must be between 0 and 1");
  }
  if (mirrorMinimumMatches < 1) throw new RangeError("mirrorMinimumMatches must be at least 1");
  if (mirrorMinimumSignatures < 1) throw new RangeError("mirrorMinimumSignatures must be at least 1");
  return {
    mirrorWindowMs,
    mirrorMatchThreshold,
    mirrorMinimumMatches: Math.trunc(mirrorMinimumMatches),
    mirrorMinimumSignatures: Math.trunc(mirrorMinimumSignatures)
  };
}

function normalizeSession(rawSession) {
  const session = isPlainObject(rawSession) ? rawSession : {};
  return {
    startedAt: stringOrNull(session.startedAt),
    savedAt: stringOrNull(session.savedAt),
    durationMs: finiteOrNull(session.durationMs),
    launcherBackend: stringOrNull(session.launcherBackend),
    sysexEnabled: booleanOrNull(session.sysexEnabled),
    browserUserAgent: stringOrNull(session.browserUserAgent),
    rawEventLimit: finiteOrNull(session.rawEventLimit),
    rawEventsDropped: finiteOrNull(session.rawEventsDropped),
    physicalInputLatencyMeasured: booleanOrNull(session.physicalInputLatencyMeasured),
    metadata: normalizeScalarRecord(session.metadata)
  };
}

function normalizeNoMidiObservations(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(isPlainObject).map((item) => ({
    trialId: stringOrNull(item.trialId) ?? stringOrNull(item.id),
    trialKey: stringOrNull(item.trialKey) ?? stringOrNull(item.planKey) ?? stringOrNull(item.key),
    label: stringOrNull(item.label),
    result: stringOrNull(item.result) ?? "no-midi-observed",
    observation: stringOrNull(item.observation) ?? stringOrNull(item.notes),
    recordedAtMs: finiteOrNull(item.recordedAtMs)
  }));
}

function normalizeOutputProbes(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(isPlainObject).map((item, index) => {
    const cleanupComplete = booleanOrNull(item.cleanupComplete);
    const cleanupError = stringOrNull(item.cleanupError);
    const outputClosed = booleanOrNull(item.outputClosed);
    const closeError = stringOrNull(item.closeError);
    return {
      id: stringOrNull(item.id) ?? `probe-${index + 1}`,
      outputRef: stringOrNull(item.outputRef) ?? MISSING_PORT,
      channel: finiteOrNull(item.channel),
      note: finiteOrNull(item.note),
      velocity: finiteOrNull(item.velocity),
      sentAtMs: finiteOrNull(item.sentAtMs),
      observedAtMs: finiteOrNull(item.observedAtMs),
      noteLengthMs: finiteOrNull(item.noteLengthMs),
      result: stringOrNull(item.result),
      observation: stringOrNull(item.observation) ?? stringOrNull(item.notes),
      noteOnSent: booleanOrNull(item.noteOnSent),
      noteOffSent: booleanOrNull(item.noteOffSent),
      allNotesOffSent: booleanOrNull(item.allNotesOffSent),
      allSoundOffSent: booleanOrNull(item.allSoundOffSent),
      messagesSent: finiteOrNull(item.messagesSent),
      cleanupComplete,
      cleanupStatus: cleanupComplete === true
        ? "complete"
        : cleanupComplete === false || cleanupError
          ? "incomplete"
          : "unknown",
      sendError: stringOrNull(item.sendError),
      cleanupError,
      outputClosed,
      outputCloseStatus: outputClosed === true
        ? "closed"
        : closeError
          ? "close-error"
          : outputClosed === false
            ? "not-closed"
            : "unknown",
      closeError
    };
  });
}

function normalizeOutputCleanupActions(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(isPlainObject).map((item) => {
    const errors = normalizeStringList(item.errors);
    const clearCalled = booleanOrNull(item.clearCalled);
    const allNotesOffSent = finiteOrNull(item.allNotesOffSent);
    const allSoundOffSent = finiteOrNull(item.allSoundOffSent);
    const hasCleanupEvidence = clearCalled !== null
      || finiteOrNull(item.messagesSent) !== null
      || allNotesOffSent !== null
      || allSoundOffSent !== null;
    const explicitComplete = booleanOrNull(item.cleanupComplete);
    const inferredComplete = clearCalled === true
      && allNotesOffSent !== null && allNotesOffSent >= 16
      && allSoundOffSent !== null && allSoundOffSent >= 16
      && errors.length === 0;
    return {
      atMs: finiteOrNull(item.atMs),
      reason: stringOrNull(item.reason),
      outputRef: stringOrNull(item.outputRef) ?? MISSING_PORT,
      clearCalled,
      noteOffsSent: finiteOrNull(item.noteOffsSent),
      allNotesOffSent,
      allSoundOffSent,
      messagesSent: finiteOrNull(item.messagesSent),
      errors,
      cleanupStatus: errors.length > 0 || explicitComplete === false
        ? "errors"
        : explicitComplete === true
          ? "complete"
          : inferredComplete
            ? "complete"
            : hasCleanupEvidence
              ? "partial"
              : "unknown"
    };
  });
}

function correlatePortTransitions(value, trials) {
  if (!Array.isArray(value)) return [];
  return value.filter(isPlainObject).map((item) => {
    const atMs = finiteOrNull(item.atMs);
    const hasExplicitTrialContext = Object.hasOwn(item, "trialId")
      || Object.hasOwn(item, "trialKey")
      || Object.hasOwn(item, "planKey");
    const explicitTrialId = stringOrNull(item.trialId);
    const explicitTrialKey = stringOrNull(item.trialKey) ?? stringOrNull(item.planKey);
    let correlatedTrial = null;
    let trialCorrelation = "none";

    if (hasExplicitTrialContext) {
      if (explicitTrialId) {
        correlatedTrial = trials.find((trial) => trial.trialId === explicitTrialId) ?? null;
        trialCorrelation = correlatedTrial
          ? explicitTrialKey && correlatedTrial.trialKey !== explicitTrialKey
            ? "explicit-id-key-mismatch"
            : "explicit"
          : "explicit-unresolved";
      } else if (explicitTrialKey) {
        const keyMatches = trials.filter((trial) => trial.trialKey === explicitTrialKey);
        correlatedTrial = keyMatches.length === 1 ? keyMatches[0] : null;
        trialCorrelation = keyMatches.length === 1
          ? "explicit"
          : keyMatches.length > 1
            ? "explicit-ambiguous-key"
            : "explicit-unresolved";
      } else {
        trialCorrelation = "explicit-none";
      }
    } else if (atMs !== null) {
      const timedMatches = trials.filter((trial) => trial.startedAtMs !== null
        && trial.endedAtMs !== null
        && atMs >= trial.startedAtMs
        && atMs <= trial.endedAtMs);
      if (timedMatches.length === 1) {
        [correlatedTrial] = timedMatches;
        trialCorrelation = "time-range";
      } else if (timedMatches.length > 1) {
        trialCorrelation = "ambiguous-time-range";
      }
    }

    return {
      atMs,
      portRef: stringOrNull(item.portRef) ?? stringOrNull(item.ref) ?? MISSING_PORT,
      direction: stringOrNull(item.direction),
      name: stringOrNull(item.name),
      manufacturer: stringOrNull(item.manufacturer),
      state: stringOrNull(item.state),
      connection: stringOrNull(item.connection),
      trialId: explicitTrialId,
      trialKey: explicitTrialKey,
      correlatedTrialId: correlatedTrial?.trialId ?? explicitTrialId,
      correlatedTrialKey: correlatedTrial?.trialKey ?? explicitTrialKey,
      correlatedTrialLabel: correlatedTrial?.label ?? null,
      trialCorrelation
    };
  });
}

function summarizeParseDiagnostics(events) {
  const mismatchFieldCounts = {};
  const mismatches = [];
  for (const event of events) {
    if (event.parsedMismatchFields.length === 0) continue;
    mismatches.push({
      sequence: event.sequence,
      portRef: event.portRef,
      fields: [...event.parsedMismatchFields]
    });
    for (const field of event.parsedMismatchFields) {
      mismatchFieldCounts[field] = (mismatchFieldCounts[field] ?? 0) + 1;
    }
  }
  return {
    rawDecodedEventCount: events.filter((event) => event.parsedSource === "raw-bytes").length,
    suppliedFallbackEventCount: events.filter((event) => event.parsedSource === "supplied-or-unknown").length,
    invalidRawEventCount: events.filter((event) => event.parsedSource === "invalid-raw-bytes").length,
    mismatchEventCount: mismatches.length,
    mismatchFieldCounts,
    mismatches
  };
}

function normalizeDecodedMessage(decoded) {
  return {
    category: stringOrNull(decoded.category) ?? "unknown",
    messageType: stringOrNull(decoded.messageType) ?? "unknown",
    phase: stringOrNull(decoded.phase) ?? "event",
    channel: finiteOrNull(decoded.channel),
    number: finiteOrNull(decoded.number),
    value: finiteOrNull(decoded.value),
    velocity: finiteOrNull(decoded.velocity),
    signalKey: stringOrNull(decoded.signalKey) ?? "unknown"
  };
}

function normalizeSuppliedMessage(supplied) {
  return {
    category: stringOrNull(supplied.category) ?? "unknown",
    messageType: stringOrNull(supplied.messageType) ?? "unknown",
    phase: stringOrNull(supplied.phase) ?? "event",
    channel: finiteOrNull(supplied.channel),
    number: finiteOrNull(supplied.number),
    value: finiteOrNull(supplied.value),
    velocity: finiteOrNull(supplied.velocity),
    signalKey: stringOrNull(supplied.signalKey) ?? "unknown"
  };
}

function findParsedMismatches(supplied, canonical) {
  const mismatches = [];
  for (const field of PARSED_FIELD_NAMES) {
    if (!Object.hasOwn(supplied, field)) continue;
    const suppliedValue = parsedFieldValue(field, supplied[field]);
    if (!Object.is(suppliedValue, canonical[field])) mismatches.push(field);
  }
  return mismatches;
}

function parsedFieldValue(field, value) {
  return field === "category" || field === "messageType" || field === "phase" || field === "signalKey"
    ? stringOrNull(value)
    : finiteOrNull(value);
}

function normalizeEvent(rawEvent, index) {
  const raw = isPlainObject(rawEvent) ? rawEvent : {};
  const invalidByteData = hasInvalidMidiBytes(raw.bytes);
  const bytes = normalizeBytes(raw.bytes);
  const eventTimestampMs = finiteOrNull(raw.eventTimestampMs);
  const receivedAtMs = finiteOrNull(raw.receivedAtMs);
  const callbackDelayMs = finiteOrNull(raw.callbackDelayMs)
    ?? (eventTimestampMs !== null && receivedAtMs !== null
      ? roundNumber(receivedAtMs - eventTimestampMs)
      : null);
  const invalidRawMessage = invalidByteData || (bytes.length > 0 && !hasCompleteMidiMessage(bytes));
  const decoded = bytes.length > 0 && !invalidRawMessage
    ? parseMidiMessage(bytes, eventTimestampMs ?? 0)
    : null;
  const supplied = isPlainObject(raw.parsed) ? raw.parsed : {};
  const parsed = invalidRawMessage
    ? {
        category: "invalid",
        messageType: "truncated",
        phase: "event",
        channel: null,
        number: null,
        value: null,
        velocity: null,
        signalKey: "invalid:truncated"
      }
    : decoded
      ? normalizeDecodedMessage(decoded)
      : normalizeSuppliedMessage(supplied);
  const parsedMismatchFields = decoded || invalidRawMessage
    ? findParsedMismatches(supplied, parsed)
    : [];

  return {
    originalIndex: index,
    sequence: finiteOrNull(raw.sequence) ?? index + 1,
    portRef: stringOrNull(raw.portRef) ?? MISSING_PORT,
    eventTimestampMs,
    receivedAtMs,
    callbackDelayMs,
    bytes,
    invalidRawMessage,
    parsedSource: invalidRawMessage ? "invalid-raw-bytes" : decoded ? "raw-bytes" : "supplied-or-unknown",
    parsedMismatchFields,
    parsed,
    trialId: stringOrNull(raw.trialId),
    trialKey: stringOrNull(raw.trialKey)
  };
}

function normalizePorts(rawPorts) {
  const source = isPlainObject(rawPorts) ? rawPorts : {};
  return {
    inputs: normalizePortList(source.inputs, "input"),
    outputs: normalizePortList(source.outputs, "output")
  };
}

function normalizePortList(value, direction) {
  if (!Array.isArray(value)) return [];
  return value.filter(isPlainObject).map((port, index) => {
    return {
      direction,
      portRef: stringOrNull(port.portRef) ?? stringOrNull(port.ref) ?? stringOrNull(port.id) ?? `${direction}-${index + 1}`,
      name: stringOrNull(port.name) ?? "",
      manufacturer: stringOrNull(port.manufacturer) ?? "",
      state: stringOrNull(port.state),
      connection: stringOrNull(port.connection)
    };
  });
}

function normalizeTrials(rawTrials) {
  if (!Array.isArray(rawTrials)) return [];
  return rawTrials.filter(isPlainObject).map((trial, index) => {
    return {
      trialId: stringOrNull(trial.trialId) ?? stringOrNull(trial.id) ?? `trial-${index + 1}`,
      trialKey: stringOrNull(trial.trialKey) ?? stringOrNull(trial.planKey) ?? stringOrNull(trial.key),
      group: stringOrNull(trial.group),
      label: stringOrNull(trial.label) ?? "",
      status: stringOrNull(trial.status) ?? stringOrNull(trial.result),
      observation: stringOrNull(trial.observation) ?? stringOrNull(trial.notes),
      instructions: stringOrNull(trial.instructions),
      startedAtMs: finiteOrNull(trial.startedAtMs),
      endedAtMs: finiteOrNull(trial.endedAtMs),
      startSequence: finiteOrNull(trial.startSequence),
      endSequence: finiteOrNull(trial.endSequence),
      declaredEventCount: finiteOrNull(trial.eventCount),
      declaredMeaningfulEventCount: finiteOrNull(trial.meaningfulEventCount),
      declaredPortRefs: normalizeStringList(trial.portRefs),
      declaredSignalRefs: normalizeStringList(trial.signalRefs)
    };
  });
}

function buildPortSummaries(events, ports) {
  const inputByRef = new Map(ports.inputs.map((port) => [port.portRef, port]));
  const observedRefs = uniqueStrings(events.map((event) => event.portRef));
  const inputRefs = uniqueStrings([...ports.inputs.map((port) => port.portRef), ...observedRefs]);
  const summaries = inputRefs.map((portRef) => {
    const port = inputByRef.get(portRef);
    const groupedEvents = events.filter((event) => event.portRef === portRef);
    return {
      ...port,
      direction: "input",
      portRef,
      declared: Boolean(port),
      ...summarizeEventSet(groupedEvents)
    };
  });

  for (const port of ports.outputs) {
    summaries.push({
      ...port,
      declared: true,
      ...summarizeEventSet([])
    });
  }
  return summaries.sort(comparePortSummaries);
}

function summarizeGroups(events, keySelector, extraBuilder) {
  const groups = new Map();
  for (const event of events) {
    const keyParts = keySelector(event);
    const key = JSON.stringify(keyParts);
    if (!groups.has(key)) groups.set(key, { keyParts, events: [] });
    groups.get(key).events.push(event);
  }
  return [...groups.values()].map(({ keyParts, events: groupedEvents }) => ({
    ...extraBuilder(keyParts, groupedEvents),
    ...summarizeEventSet(groupedEvents)
  })).sort(compareSummaryRows);
}

function summarizeEventSet(events) {
  const timestamps = events.map((event) => event.eventTimestampMs).filter(isFiniteNumber);
  const sortedTimestamps = [...timestamps].sort((a, b) => a - b);
  const firstEventTimestampMs = sortedTimestamps[0] ?? null;
  const lastEventTimestampMs = sortedTimestamps.at(-1) ?? null;
  const stepSegments = events.map((event) => JSON.stringify([
    event.portRef,
    trialGroupKey(event),
    event.parsed.signalKey || fallbackSignalKey(event.parsed)
  ]));
  return {
    eventCount: events.length,
    firstEventTimestampMs,
    lastEventTimestampMs,
    durationMs: firstEventTimestampMs !== null && lastEventTimestampMs !== null
      ? roundNumber(lastEventTimestampMs - firstEventTimestampMs)
      : null,
    categories: uniqueStrings(events.map((event) => event.parsed.category)),
    messageTypes: uniqueStrings(events.map((event) => event.parsed.messageType)),
    signalCount: new Set(events.map((event) => event.parsed.signalKey || fallbackSignalKey(event.parsed))).size,
    trialCount: new Set(events.map(trialGroupKey)).size,
    valueSummary: summarizeNumericValues(
      events.map((event) => event.parsed.phase === "release" ? null : event.parsed.value),
      stepSegments
    ),
    rawValueSummary: summarizeNumericValues(events.map((event) => event.parsed.value), stepSegments),
    velocitySummary: summarizeNumericValues(events.map((event) => event.parsed.velocity), stepSegments),
    callbackDelaySummary: summarizeDistribution(events.map((event) => event.callbackDelayMs))
  };
}

function summarizeSelectedValues(events, predicate, selector) {
  const selected = events.filter(predicate);
  return summarizeNumericValues(
    selected.map(selector),
    selected.map((event) => trialGroupKey(event))
  );
}

function buildTrialSummaries(events, declaredTrials, noMidiObservations = []) {
  const groups = new Map();
  const declaredById = new Map();
  const declaredByKey = new Map();
  for (const trial of declaredTrials) {
    declaredById.set(trial.trialId, trial);
    if (trial.trialKey && !declaredByKey.has(trial.trialKey)) declaredByKey.set(trial.trialKey, trial);
    groups.set(trial.trialId, { trial, events: [] });
  }

  for (const event of events) {
    const declared = (event.trialId && declaredById.get(event.trialId))
      || (!event.trialId && event.trialKey && declaredByKey.get(event.trialKey));
    const groupId = declared?.trialId
      ?? event.trialId
      ?? (event.trialKey ? `key:${event.trialKey}` : UNASSIGNED_TRIAL);
    if (!groups.has(groupId)) {
      groups.set(groupId, {
        trial: {
          trialId: event.trialId ?? groupId,
          trialKey: event.trialKey,
          group: null,
          label: "",
          status: null,
          observation: null,
          instructions: null,
          startedAtMs: null,
          endedAtMs: null,
          startSequence: null,
          endSequence: null,
          declaredEventCount: null,
          declaredMeaningfulEventCount: null,
          declaredPortRefs: [],
          declaredSignalRefs: []
        },
        events: []
      });
    }
    groups.get(groupId).events.push(event);
  }

  return [...groups.values()].map(({ trial, events: groupedEvents }) => {
    const explicitNoMidi = noMidiObservations.filter((item) => (
      item.trialId && item.trialId === trial.trialId
    ) || (
      !item.trialId && item.trialKey && item.trialKey === trial.trialKey
    ));
    const noMidiObservationText = explicitNoMidi
      .map((item) => item.observation)
      .filter(Boolean)
      .join("; ");
    return {
      ...trial,
      status: trial.status ?? explicitNoMidi[0]?.result ?? null,
      observation: (trial.observation ?? noMidiObservationText) || null,
      declared: declaredById.has(trial.trialId),
      noMidiObserved: explicitNoMidi.length > 0 || trial.status === "no-midi-observed",
      noMidiObservations: explicitNoMidi,
      portRefs: uniqueStrings([
        ...trial.declaredPortRefs,
        ...groupedEvents.map((event) => event.portRef)
      ]),
      noteSummary: analyzeNotes(groupedEvents).totals,
      ...summarizeEventSet(groupedEvents)
    };
  }).sort((a, b) => a.trialId.localeCompare(b.trialId));
}

function analyzeNotes(events) {
  const byPortAndTrial = new Map();
  for (const event of events) {
    if (!isNoteOn(event.parsed) && !isNoteOff(event.parsed)) continue;
    const groupKey = JSON.stringify([event.portRef, event.trialId, event.trialKey]);
    if (!byPortAndTrial.has(groupKey)) {
      byPortAndTrial.set(groupKey, {
        portRef: event.portRef,
        trialId: event.trialId,
        trialKey: event.trialKey,
        events: []
      });
    }
    byPortAndTrial.get(groupKey).events.push(event);
  }

  const internalPerTrial = [...byPortAndTrial.values()].map((group) => ({
    portRef: group.portRef,
    trialId: group.trialId,
    trialKey: group.trialKey,
    ...analyzeNoteLifecycle(group.events)
  }));
  const portGroups = new Map();
  for (const summary of internalPerTrial) {
    if (!portGroups.has(summary.portRef)) portGroups.set(summary.portRef, []);
    portGroups.get(summary.portRef).push(summary);
  }
  const internalPerPort = [...portGroups.entries()].map(([portRef, summaries]) => ({
    portRef,
    ...combineNoteSummaries(summaries)
  }));
  const totalInternal = combineNoteSummaries(internalPerPort);
  return {
    totals: {
      ...stripInternalNoteFields(totalInternal),
      maximumConcurrentNotesOnAnyPort: totalInternal.maxConcurrentNotes,
      maximumConcurrentDistinctNotesOnAnyPort: totalInternal.maxConcurrentDistinctNotes
    },
    perPort: internalPerPort
      .map(stripInternalNoteFields)
      .sort((a, b) => a.portRef.localeCompare(b.portRef)),
    perTrial: internalPerTrial
      .map(stripInternalNoteFields)
      .sort((a, b) => a.portRef.localeCompare(b.portRef)
        || (a.trialId ?? "").localeCompare(b.trialId ?? "")
        || (a.trialKey ?? "").localeCompare(b.trialKey ?? ""))
  };
}

function analyzeNoteLifecycle(noteEvents) {
  const active = new Map();
  const durations = [];
  const unmatchedNoteOffSequences = [];
  let noteOnCount = 0;
  let noteOffCount = 0;
  let pairedCount = 0;
  let repeatedNoteOnCount = 0;
  let unusableNoteEventCount = 0;
  let invalidDurationCount = 0;
  let concurrent = 0;
  let maxConcurrentNotes = 0;
  let maxConcurrentDistinctNotes = 0;

  for (const event of noteEvents) {
    if (!isFiniteNumber(event.parsed.channel) || !isFiniteNumber(event.parsed.number)) {
      unusableNoteEventCount += 1;
      continue;
    }
    const key = `${event.parsed.channel}:${event.parsed.number}`;
    if (isNoteOn(event.parsed)) {
      noteOnCount += 1;
      const queue = active.get(key) ?? [];
      if (queue.length > 0) repeatedNoteOnCount += 1;
      queue.push(event);
      active.set(key, queue);
      concurrent += 1;
      maxConcurrentNotes = Math.max(maxConcurrentNotes, concurrent);
      maxConcurrentDistinctNotes = Math.max(maxConcurrentDistinctNotes, active.size);
      continue;
    }

    noteOffCount += 1;
    const queue = active.get(key);
    if (!queue || queue.length === 0) {
      unmatchedNoteOffSequences.push(event.sequence);
      continue;
    }
    const start = queue.shift();
    pairedCount += 1;
    concurrent = Math.max(0, concurrent - 1);
    const startTime = eventClockTime(start);
    const endTime = eventClockTime(event);
    if (startTime !== null && endTime !== null && endTime >= startTime) {
      durations.push(roundNumber(endTime - startTime));
    } else {
      invalidDurationCount += 1;
    }
    if (queue.length === 0) active.delete(key);
  }

  const unmatchedNoteOnSequences = [...active.values()]
    .flat()
    .map((event) => event.sequence)
    .sort((a, b) => a - b);
  return {
    noteOnCount,
    noteOffCount,
    pairedCount,
    repeatedNoteOnCount,
    unusableNoteEventCount,
    invalidDurationCount,
    unmatchedNoteOnCount: unmatchedNoteOnSequences.length,
    unmatchedNoteOffCount: unmatchedNoteOffSequences.length,
    unmatchedNoteOnSequences,
    unmatchedNoteOffSequences,
    maxConcurrentNotes,
    maxConcurrentDistinctNotes,
    durationSummary: summarizeDistribution(durations),
    _durations: durations
  };
}

function combineNoteSummaries(summaries) {
  const durations = summaries.flatMap((summary) => summary._durations ?? []);
  return {
    noteOnCount: sum(summaries, "noteOnCount"),
    noteOffCount: sum(summaries, "noteOffCount"),
    pairedCount: sum(summaries, "pairedCount"),
    repeatedNoteOnCount: sum(summaries, "repeatedNoteOnCount"),
    unusableNoteEventCount: sum(summaries, "unusableNoteEventCount"),
    invalidDurationCount: sum(summaries, "invalidDurationCount"),
    unmatchedNoteOnCount: sum(summaries, "unmatchedNoteOnCount"),
    unmatchedNoteOffCount: sum(summaries, "unmatchedNoteOffCount"),
    unmatchedNoteOnSequences: summaries.flatMap((summary) => summary.unmatchedNoteOnSequences ?? []).sort((a, b) => a - b),
    unmatchedNoteOffSequences: summaries.flatMap((summary) => summary.unmatchedNoteOffSequences ?? []).sort((a, b) => a - b),
    maxConcurrentNotes: summaries.length > 0 ? Math.max(...summaries.map((summary) => summary.maxConcurrentNotes)) : 0,
    maxConcurrentDistinctNotes: summaries.length > 0
      ? Math.max(...summaries.map((summary) => summary.maxConcurrentDistinctNotes))
      : 0,
    durationSummary: summarizeDistribution(durations),
    _durations: durations
  };
}

function stripInternalNoteFields(summary) {
  const { _durations, ...publicSummary } = summary;
  return publicSummary;
}

function analyzeMirrorPairs(events, options) {
  const byPort = new Map();
  for (const event of events) {
    if (event.portRef === MISSING_PORT) continue;
    if (!byPort.has(event.portRef)) byPort.set(event.portRef, []);
    byPort.get(event.portRef).push(event);
  }
  const portRefs = [...byPort.keys()].sort();
  const pairs = [];
  for (let left = 0; left < portRefs.length; left += 1) {
    for (let right = left + 1; right < portRefs.length; right += 1) {
      pairs.push(compareMirrorPair(
        portRefs[left],
        byPort.get(portRefs[left]),
        portRefs[right],
        byPort.get(portRefs[right]),
        options
      ));
    }
  }
  return pairs.sort((a, b) => Number(b.isCandidate) - Number(a.isCandidate)
    || b.strictMatchRate - a.strictMatchRate
    || a.portA.localeCompare(b.portA)
    || a.portB.localeCompare(b.portB));
}

function compareMirrorPair(portA, eventsA, portB, eventsB, options) {
  const comparableResultA = comparableMirrorEvents(eventsA);
  const comparableResultB = comparableMirrorEvents(eventsB);
  const comparableA = comparableResultA.groups;
  const comparableB = comparableResultB.groups;
  const signatures = new Set([...comparableA.keys(), ...comparableB.keys()]);
  const skews = [];
  const matchedRawSignatures = new Set();
  let matchedCount = 0;

  for (const signature of signatures) {
    const left = comparableA.get(signature) ?? [];
    const right = comparableB.get(signature) ?? [];
    let leftIndex = 0;
    let rightIndex = 0;
    let signatureMatches = 0;
    while (leftIndex < left.length && rightIndex < right.length) {
      const skew = right[rightIndex].time - left[leftIndex].time;
      if (Math.abs(skew) <= options.mirrorWindowMs) {
        skews.push(roundNumber(skew));
        matchedCount += 1;
        signatureMatches += 1;
        leftIndex += 1;
        rightIndex += 1;
      } else if (left[leftIndex].time < right[rightIndex].time) {
        leftIndex += 1;
      } else {
        rightIndex += 1;
      }
    }
    if (signatureMatches > 0) {
      const [, bytes] = JSON.parse(signature);
      matchedRawSignatures.add(bytes.join(","));
    }
  }

  const matchedSignatureCount = matchedRawSignatures.size;
  const comparableEventCountA = comparableResultA.eligibleCount;
  const comparableEventCountB = comparableResultB.eligibleCount;
  const matchRateA = rate(matchedCount, comparableEventCountA);
  const matchRateB = rate(matchedCount, comparableEventCountB);
  const strictMatchRate = rate(matchedCount, Math.max(comparableEventCountA, comparableEventCountB));
  const symmetricMatchRate = rate(2 * matchedCount, comparableEventCountA + comparableEventCountB);
  const isCandidate = matchedCount >= options.mirrorMinimumMatches
    && matchedSignatureCount >= options.mirrorMinimumSignatures
    && matchRateA >= options.mirrorMatchThreshold
    && matchRateB >= options.mirrorMatchThreshold;

  return {
    portA,
    portB,
    eventCountA: eventsA.length,
    eventCountB: eventsB.length,
    comparableEventCountA,
    comparableEventCountB,
    matchedCount,
    matchedSignatureCount,
    excludedEventCountA: comparableResultA.excludedCount,
    excludedEventCountB: comparableResultB.excludedCount,
    matchRateA,
    matchRateB,
    strictMatchRate,
    symmetricMatchRate,
    skewSummary: summarizeDistribution(skews),
    absoluteSkewSummary: summarizeDistribution(skews.map(Math.abs)),
    isCandidate
  };
}

function comparableMirrorEvents(events) {
  const grouped = new Map();
  let eligibleCount = 0;
  let excludedCount = 0;
  for (const event of events) {
    const time = eventClockTime(event);
    const isSystemNoise = event.parsed.category === "system"
      && (event.parsed.messageType === "timing-clock" || event.parsed.messageType === "active-sensing");
    if (time === null || event.bytes.length === 0 || event.invalidRawMessage || isSystemNoise) {
      excludedCount += 1;
      continue;
    }
    const signature = JSON.stringify([trialGroupKey(event), event.bytes]);
    if (!grouped.has(signature)) grouped.set(signature, []);
    grouped.get(signature).push({ time, sequence: event.sequence });
    eligibleCount += 1;
  }
  for (const group of grouped.values()) {
    group.sort((a, b) => a.time - b.time || a.sequence - b.sequence);
  }
  return { groups: grouped, eligibleCount, excludedCount };
}

function buildLimitations(source, rawEvents, events, ports, context = {}) {
  const parseDiagnostics = context.parseDiagnostics ?? {};
  const outputProbeSummaries = context.outputProbeSummaries ?? [];
  const outputCleanupActions = context.outputCleanupActions ?? [];
  const limitations = [
    "Only observed messages are summarized; an unexercised control or mode cannot be classified as unsupported.",
    "Observed value ranges and steps are not guaranteed hardware limits or resolution.",
    "Callback delay is browser scheduling delay, not physical key-to-host latency.",
    "Mirror candidates are timing-and-byte heuristics; retain every source stream and confirm with repeated varied trials before deduplicating.",
    "Input events alone do not establish output behavior, SysEx or MIDI-CI support, MIDI 2.0 or UMP support, or non-MIDI HID and audio capabilities."
  ];
  if (source.schemaVersion !== 2) {
    limitations.push(`Expected inventory schemaVersion 2; received ${source.schemaVersion ?? "none"}.`);
  }
  if (!Array.isArray(source.rawEvents)) {
    limitations.push("The inventory has no rawEvents array.");
  } else if (rawEvents.length === 0) {
    limitations.push("The rawEvents array is empty.");
  }
  const missingPortRefs = events.filter((event) => event.portRef === MISSING_PORT).length;
  const missingTimestamps = events.filter((event) => eventClockTime(event) === null).length;
  const missingBytes = events.filter((event) => event.bytes.length === 0).length;
  const missingDelays = events.filter((event) => event.callbackDelayMs === null).length;
  const truncatedMessages = events.filter((event) => event.invalidRawMessage).length;
  if (missingPortRefs > 0) limitations.push(`${missingPortRefs} event(s) lack a portRef.`);
  if (missingTimestamps > 0) limitations.push(`${missingTimestamps} event(s) lack a usable timestamp.`);
  if (missingBytes > 0) limitations.push(`${missingBytes} event(s) lack raw bytes and cannot contribute to mirror matching.`);
  if (missingDelays > 0) limitations.push(`${missingDelays} event(s) lack callback-delay data.`);
  if (truncatedMessages > 0) limitations.push(`${truncatedMessages} truncated or invalid raw message(s) were not interpreted as MIDI capabilities.`);
  if ((parseDiagnostics.mismatchEventCount ?? 0) > 0) {
    limitations.push(`${parseDiagnostics.mismatchEventCount} event(s) had supplied parsed fields that disagreed with raw MIDI bytes; raw-byte decoding was used.`);
  }
  if (ports.outputs.length === 0 && outputProbeSummaries.length === 0) {
    limitations.push("No output ports or output probes were declared, so output behavior was not assessed.");
  } else if (ports.outputs.length === 0) {
    limitations.push("Output probes were recorded without declared output-port metadata.");
  } else if (outputProbeSummaries.length === 0) {
    limitations.push("Output ports were declared, but no output probes were recorded.");
  }
  const uncertainProbeCleanup = outputProbeSummaries.filter((probe) => probe.cleanupStatus !== "complete").length;
  const uncertainProbeClosure = outputProbeSummaries.filter((probe) => (
    probe.outputCloseStatus === "close-error" || probe.outputCloseStatus === "not-closed"
  )).length;
  const uncertainCleanupActions = outputCleanupActions.filter((action) => action.cleanupStatus !== "complete").length;
  if (uncertainProbeCleanup > 0) {
    limitations.push(`${uncertainProbeCleanup} output probe(s) lack confirmed complete note cleanup.`);
  }
  if (uncertainProbeClosure > 0) {
    limitations.push(`${uncertainProbeClosure} output probe(s) report an output-port close problem.`);
  }
  if (uncertainCleanupActions > 0) {
    limitations.push(`${uncertainCleanupActions} output cleanup action(s) were partial, failed, or unverifiable.`);
  }
  if (source.rawEventsTruncated === true
    || source.truncated === true
    || source.capture?.rawEventsTruncated === true
    || (isFiniteNumber(source.session?.rawEventsDropped) && source.session.rawEventsDropped > 0)) {
    limitations.push("The inventory reports that raw events were truncated.");
  }
  for (const limitation of normalizeStringList(source.limitations)) {
    if (!limitations.includes(limitation)) limitations.push(limitation);
  }
  return limitations;
}

function summarizeDistribution(values) {
  const sorted = values.filter(isFiniteNumber).map(Number).sort((a, b) => a - b);
  if (sorted.length === 0) {
    return { count: 0, min: null, max: null, mean: null, median: null, p95: null, p99: null };
  }
  return {
    count: sorted.length,
    min: sorted[0],
    max: sorted.at(-1),
    mean: roundNumber(sorted.reduce((sumValue, value) => sumValue + value, 0) / sorted.length),
    median: quantile(sorted, 0.5),
    p95: quantile(sorted, 0.95),
    p99: quantile(sorted, 0.99)
  };
}

function quantile(sorted, probability) {
  if (sorted.length === 0) return null;
  if (sorted.length === 1) return sorted[0];
  const position = (sorted.length - 1) * probability;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower];
  const weight = position - lower;
  return roundNumber(sorted[lower] * (1 - weight) + sorted[upper] * weight);
}

function mode(values) {
  if (values.length === 0) return null;
  const counts = new Map();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0][0];
}

function emptyStepSummary() {
  return {
    adjacentDistinctSteps: [],
    smallestObservedStep: null,
    largestObservedStep: null,
    transitionCount: 0,
    zeroTransitionCount: 0,
    changedTransitionCount: 0,
    smallestAbsoluteTransition: null,
    largestAbsoluteTransition: null,
    medianAbsoluteTransition: null,
    modalAbsoluteTransition: null,
    distinctSignedTransitions: []
  };
}

function isNoteOn(parsed) {
  if (parsed.category !== "note") return false;
  if (parsed.phase === "release" || parsed.messageType === "note-off") return false;
  if (parsed.messageType === "note-on" && Number(parsed.velocity ?? parsed.value) === 0) return false;
  return parsed.phase === "press" || parsed.messageType === "note-on";
}

function isNoteOff(parsed) {
  if (parsed.category !== "note") return false;
  return parsed.phase === "release"
    || parsed.messageType === "note-off"
    || (parsed.messageType === "note-on" && Number(parsed.velocity ?? parsed.value) === 0);
}

function fallbackSignalKey(parsed) {
  return `${parsed.messageType || "unknown"}:${parsed.channel ?? "?"}:${parsed.number ?? "?"}`;
}

function trialGroupKey(event) {
  return event.trialId ?? (event.trialKey ? `key:${event.trialKey}` : UNASSIGNED_TRIAL);
}

function eventClockTime(event) {
  return finiteOrNull(event.eventTimestampMs) ?? finiteOrNull(event.receivedAtMs);
}

function compareEvents(a, b) {
  if (a.sequence !== b.sequence) return a.sequence - b.sequence;
  const leftTime = eventClockTime(a);
  const rightTime = eventClockTime(b);
  if (leftTime !== null && rightTime !== null && leftTime !== rightTime) return leftTime - rightTime;
  return a.originalIndex - b.originalIndex;
}

function comparePortSummaries(a, b) {
  return a.direction.localeCompare(b.direction) || a.portRef.localeCompare(b.portRef);
}

function compareSummaryRows(a, b) {
  return (a.portRef ?? "").localeCompare(b.portRef ?? "")
    || (a.messageType ?? a.signalKey ?? "").localeCompare(b.messageType ?? b.signalKey ?? "");
}

function normalizeBytes(value) {
  if (!Array.isArray(value) && !ArrayBuffer.isView(value)) return [];
  const bytes = Array.from(value, (byte) => Number(byte));
  return bytes.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 0xff) ? bytes : [];
}

function hasInvalidMidiBytes(value) {
  if (!Array.isArray(value) && !ArrayBuffer.isView(value)) return false;
  return Array.from(value, (byte) => Number(byte))
    .some((byte) => !Number.isInteger(byte) || byte < 0 || byte > 0xff);
}

function hasCompleteMidiMessage(bytes) {
  const status = bytes[0];
  if (!Number.isInteger(status) || status < 0x80) return false;
  if (status < 0xf0) {
    const family = status & 0xf0;
    const requiredLength = family === 0xc0 || family === 0xd0 ? 2 : 3;
    return bytes.length === requiredLength && bytes.slice(1).every((byte) => byte < 0x80);
  }
  if (status === 0xf0) {
    return bytes.length >= 2
      && bytes.at(-1) === 0xf7
      && bytes.slice(1, -1).every((byte) => byte < 0x80);
  }
  if (status === 0xf1 || status === 0xf3) return bytes.length === 2 && bytes[1] < 0x80;
  if (status === 0xf2) return bytes.length === 3 && bytes[1] < 0x80 && bytes[2] < 0x80;
  return bytes.length === 1;
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.length > 0))].sort();
}

function uniqueNumbers(values) {
  return [...new Set(values.filter(isFiniteNumber).map(Number))].sort((a, b) => a - b);
}

function normalizeStringList(value) {
  const source = Array.isArray(value) ? value : typeof value === "string" ? [value] : [];
  return uniqueStrings(source.map((item) => stringOrNull(item)));
}

function normalizeScalarRecord(value) {
  if (!isPlainObject(value)) return {};
  const result = {};
  for (const [key, rawValue] of Object.entries(value)) {
    if (typeof rawValue === "string") {
      const normalized = stringOrNull(rawValue);
      if (normalized !== null) result[key] = normalized;
    } else if (typeof rawValue === "boolean" || isFiniteNumber(rawValue)) {
      result[key] = rawValue;
    }
  }
  return result;
}

function booleanOrNull(value) {
  return typeof value === "boolean" ? value : null;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function stringOrNull(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function finiteOr(value, fallback) {
  return isFiniteNumber(value) ? Number(value) : fallback;
}

function finiteOrNull(value) {
  return isFiniteNumber(value) ? Number(value) : null;
}

function roundNumber(value) {
  return Number(Number(value).toFixed(6));
}

function rate(numerator, denominator) {
  return denominator > 0 ? roundNumber(numerator / denominator) : 0;
}

function sum(rows, property) {
  return rows.reduce((total, row) => total + row[property], 0);
}

function sessionMetadataRows(session) {
  if (!isPlainObject(session)) return [];
  const rows = [];
  const rootFields = [
    ["Capture started", session.startedAt],
    ["Capture saved", session.savedAt],
    ["Duration ms", session.durationMs],
    ["MIDI backend", session.launcherBackend],
    ["SysEx enabled", session.sysexEnabled],
    ["Physical input latency measured", session.physicalInputLatencyMeasured],
    ["Raw event limit", session.rawEventLimit],
    ["Raw events dropped", session.rawEventsDropped],
    ["Browser", session.browserUserAgent]
  ];
  for (const [label, value] of rootFields) {
    if (value !== null && value !== undefined && value !== "") rows.push([label, displayScalar(value)]);
  }

  const metadataLabels = {
    connectionMode: "Connection mode",
    firmwareVersion: "Firmware version",
    preset: "GLOBE preset",
    keyChannel: "GLOBE key channel",
    padChannel: "GLOBE pad channel",
    keyVelocityCurve: "GLOBE key velocity curve",
    padVelocityCurve: "GLOBE pad velocity curve",
    padAftertouch: "GLOBE pad aftertouch",
    pedalMode: "GLOBE pedal mode",
    octaveState: "Octave state",
    activeModes: "Active modes and banks",
    notes: "Session notes"
  };
  const metadata = isPlainObject(session.metadata) ? session.metadata : {};
  const orderedKeys = [
    ...Object.keys(metadataLabels),
    ...Object.keys(metadata).filter((key) => !Object.hasOwn(metadataLabels, key)).sort()
  ];
  for (const key of orderedKeys) {
    if (!Object.hasOwn(metadata, key)) continue;
    rows.push([metadataLabels[key] ?? humanizeKey(key), displayScalar(metadata[key])]);
  }
  return rows;
}

function parseDiagnosticRows(diagnostics) {
  if (!isPlainObject(diagnostics)) return [];
  const rows = [
    ["Events decoded from raw bytes", diagnostics.rawDecodedEventCount ?? 0],
    ["Events using supplied fallback", diagnostics.suppliedFallbackEventCount ?? 0],
    ["Invalid raw-byte events", diagnostics.invalidRawEventCount ?? 0],
    ["Events with parsed-field mismatches", diagnostics.mismatchEventCount ?? 0]
  ];
  for (const [field, count] of Object.entries(diagnostics.mismatchFieldCounts ?? {})) {
    rows.push([`Mismatch: ${field}`, count]);
  }
  return rows;
}

function formatProbeMessage(probe) {
  const parts = [];
  if (probe.channel !== null) parts.push(`channel ${probe.channel}`);
  if (probe.note !== null) parts.push(`note ${probe.note}`);
  if (probe.velocity !== null) parts.push(`velocity ${probe.velocity}`);
  return parts.join(" / ") || "-";
}

function booleanWord(value) {
  return value === true ? "yes" : value === false ? "no" : "unknown";
}

function displayScalar(value) {
  return typeof value === "boolean" ? booleanWord(value) : value;
}

function humanizeKey(value) {
  const words = String(value).replace(/([a-z0-9])([A-Z])/g, "$1 $2").replaceAll("_", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

function appendTable(lines, headers, rows) {
  if (rows.length === 0) {
    lines.push("_None observed._", "");
    return;
  }
  lines.push(`| ${headers.map(cell).join(" | ")} |`);
  lines.push(`| ${headers.map(() => "---").join(" | ")} |`);
  for (const row of rows) lines.push(`| ${row.map(cell).join(" | ")} |`);
  lines.push("");
}

function cell(value) {
  if (value === null || value === undefined || value === "") return "-";
  return inlineText(value).replaceAll("|", "\\|");
}

function inlineText(value) {
  return String(value)
    .replace(/[\r\n]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function numberCell(value) {
  return isFiniteNumber(value) ? String(roundNumber(value)) : "-";
}

function formatPair(left, right) {
  return `${numberCell(left)} / ${numberCell(right)}`;
}

function formatRange(summary) {
  if (!summary || summary.min === null) return "-";
  return summary.min === summary.max ? String(summary.min) : `${summary.min}...${summary.max}`;
}

function formatPercent(value) {
  return isFiniteNumber(value) ? `${roundNumber(value * 100)}%` : "-";
}
