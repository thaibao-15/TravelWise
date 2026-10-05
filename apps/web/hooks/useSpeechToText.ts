"use client";

import { useState, useRef, useCallback, useEffect } from "react";

interface UseSpeechToTextOptions {
  onTranscript: (text: string, isFinal: boolean) => void;
  onError?: (error: string) => void;
}

// Convert audio samples from hardware sampleRate (e.g. 48000/44100) down to 16000Hz 16-bit PCM
function downsampleTo16k(input: Float32Array, inputSampleRate: number): Int16Array {
  if (inputSampleRate === 16000) {
    const output = new Int16Array(input.length);
    for (let i = 0; i < input.length; i++) {
      const s = Math.max(-1, Math.min(1, input[i]));
      output[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    return output;
  }

  const ratio = inputSampleRate / 16000;
  const newLength = Math.round(input.length / ratio);
  const result = new Int16Array(newLength);

  let offsetResult = 0;
  let offsetBuffer = 0;

  while (offsetResult < result.length) {
    const nextOffsetBuffer = Math.round((offsetResult + 1) * ratio);
    let accum = 0;
    let count = 0;

    for (let i = offsetBuffer; i < nextOffsetBuffer && i < input.length; i++) {
      accum += input[i];
      count++;
    }

    const avg = count > 0 ? accum / count : 0;
    const s = Math.max(-1, Math.min(1, avg));
    result[offsetResult] = s < 0 ? s * 0x8000 : s * 0x7fff;

    offsetResult++;
    offsetBuffer = nextOffsetBuffer;
  }

  return result;
}

export function useSpeechToText({ onTranscript, onError }: UseSpeechToTextOptions) {
  const [isRecording, setIsRecording] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onTranscriptRef = useRef(onTranscript);
  onTranscriptRef.current = onTranscript;
  const onErrorRef = useRef(onError);
  onErrorRef.current = onError;

  const isRecordingRef = useRef(false);
  isRecordingRef.current = isRecording;

  const wsRef = useRef<WebSocket | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const gainRef = useRef<GainNode | null>(null);

  // Clear current error state
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  const cleanupAudioPipeline = useCallback(() => {
    if (processorRef.current) {
      try {
        processorRef.current.disconnect();
      } catch { }
      processorRef.current = null;
    }

    if (gainRef.current) {
      try {
        gainRef.current.disconnect();
      } catch { }
      gainRef.current = null;
    }

    if (sourceRef.current) {
      try {
        sourceRef.current.disconnect();
      } catch { }
      sourceRef.current = null;
    }

    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }

    if (audioContextRef.current && audioContextRef.current.state !== "closed") {
      audioContextRef.current.close().catch(() => { });
      audioContextRef.current = null;
    }
  }, []);

  const stopRecording = useCallback(() => {
    if (isRecordingRef.current) {
      setIsProcessing(true);
    }

    // 1. Send stop signal to WebSocket if still connected
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      try {
        wsRef.current.send(JSON.stringify({ type: "stop" }));
      } catch { }
    }

    // 2. Cleanup hardware microphone pipeline immediately
    cleanupAudioPipeline();

    isRecordingRef.current = false;
    setIsRecording(false);
    setIsConnecting(false);

    // Timeout safety for isProcessing
    setTimeout(() => {
      setIsProcessing(false);
    }, 2500);
  }, [cleanupAudioPipeline]);

  const startRecording = useCallback(async () => {
    clearError();
    setIsProcessing(false);

    // 1. Check browser support for getUserMedia
    if (typeof window === "undefined" || !navigator?.mediaDevices?.getUserMedia) {
      const errMsg = "Trình duyệt không hỗ trợ microphone hoặc bạn đang dùng kết nối không bảo mật (cần HTTPS hoặc localhost).";
      setError(errMsg);
      onError?.(errMsg);
      return;
    }

    setIsConnecting(true);

    let mediaStream: MediaStream;
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });
      streamRef.current = mediaStream;
    } catch (err: unknown) {
      setIsConnecting(false);
      let errMsg = "Không thể truy cập microphone.";
      if (err instanceof DOMException) {
        if (err.name === "NotAllowedError" || err.name === "PermissionDeniedError") {
          errMsg = "Quyền truy cập microphone bị từ chối. Vui lòng cấp quyền micro trong cài đặt trình duyệt để nói.";
        } else if (err.name === "NotFoundError" || err.name === "DevicesNotFoundError") {
          errMsg = "Không tìm thấy thiết bị microphone nào được kết nối với máy tính.";
        } else if (err.name === "NotReadableError" || err.name === "TrackStartError") {
          errMsg = "Microphone đang bị chiếm dụng bởi ứng dụng khác.";
        }
      }
      setError(errMsg);
      onError?.(errMsg);
      return;
    }

    // 2. Build WebSocket URL targeting FastAPI STT proxy
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
    const wsProtocol = apiUrl.startsWith("https") ? "wss:" : "ws:";
    const wsHost = apiUrl.replace(/^https?:\/\//, "").replace(/\/+$/, "");
    const wsUrl = `${wsProtocol}//${wsHost}/api/v1/stt/ws`;

    try {
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        setIsConnecting(false);
        setIsRecording(true);

        // 3. Setup lightweight Web Audio API pipeline with mute node & downsampling
        try {
          const AudioContextClass =
            window.AudioContext ||
            (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
          const audioCtx = new AudioContextClass();
          audioContextRef.current = audioCtx;

          const source = audioCtx.createMediaStreamSource(mediaStream);
          sourceRef.current = source;

          // Buffer size 4096 is standard and responsive
          const processor = audioCtx.createScriptProcessor(4096, 1, 1);
          processorRef.current = processor;

          // CRITICAL: Mute gain node prevents microphone audio looping to speakers (eliminates audio feedback/echo and driver lag)
          const muteNode = audioCtx.createGain();
          muteNode.gain.value = 0;
          gainRef.current = muteNode;

          let chunkQueue: Int16Array[] = [];
          let totalSamples = 0;
          const hardwareSampleRate = audioCtx.sampleRate;

          processor.onaudioprocess = (event) => {
            if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;

            const inputData = event.inputBuffer.getChannelData(0);
            // Downsample cleanly from hardware rate to 16000Hz PCM
            const pcm16 = downsampleTo16k(inputData, hardwareSampleRate);

            chunkQueue.push(pcm16);
            totalSamples += pcm16.length;

            // Batch and send every ~125ms (2000 samples @ 16kHz) for low transmission latency
            if (totalSamples >= 2000) {
              const merged = new Int16Array(totalSamples);
              let offset = 0;
              for (const ch of chunkQueue) {
                merged.set(ch, offset);
                offset += ch.length;
              }
              chunkQueue = [];
              totalSamples = 0;

              wsRef.current.send(merged.buffer);
            }
          };

          source.connect(processor);
          processor.connect(muteNode);
          muteNode.connect(audioCtx.destination);
        } catch (audioErr) {
          console.error("Audio pipeline initialization error:", audioErr);
          const errMsg = "Không thể khởi tạo bộ xử lý âm thanh trong trình duyệt.";
          setError(errMsg);
          onErrorRef.current?.(errMsg);
          stopRecording();
        }
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          if (data.type === "transcript") {
            if (data.text) {
              onTranscriptRef.current(data.text, !!data.is_final);
            }
            if (data.is_final) {
              setIsProcessing(false);
            }
          } else if (data.type === "status") {
            if (data.status === "stopped") {
              setIsProcessing(false);
            }
          } else if (data.type === "error") {
            const errMsg = data.message || "Xảy ra lỗi trong quá trình nhận dạng giọng nói.";
            setError(errMsg);
            onErrorRef.current?.(errMsg);
            stopRecording();
          }
        } catch (parseErr) {
          console.error("Error parsing WebSocket STT message:", parseErr);
        }
      };

      ws.onerror = (e) => {
        console.error("STT WebSocket error:", e);
        const errMsg = "Lỗi kết nối WebSocket tới dịch vụ nhận diện giọng nói.";
        setError(errMsg);
        onErrorRef.current?.(errMsg);
        stopRecording();
      };

      ws.onclose = (e) => {
        setIsProcessing(false);
        if (e.code === 1008) {
          const errMsg = "Chưa cấu hình BLAZE_API_KEY hoặc khóa không hợp lệ.";
          setError(errMsg);
          onErrorRef.current?.(errMsg);
        }
        cleanupAudioPipeline();
        isRecordingRef.current = false;
        setIsRecording(false);
        setIsConnecting(false);
      };
    } catch (wsErr) {
      console.error("Failed to create WebSocket:", wsErr);
      const errMsg = "Không thể khởi tạo kết nối WebSocket.";
      setError(errMsg);
      onErrorRef.current?.(errMsg);
      stopRecording();
    }
  }, [cleanupAudioPipeline, clearError, stopRecording]);

  // Clean up on component unmount
  useEffect(() => {
    return () => {
      cleanupAudioPipeline();
      if (wsRef.current) {
        try {
          wsRef.current.close();
        } catch { }
      }
    };
  }, [cleanupAudioPipeline]);

  return {
    isRecording,
    isConnecting,
    isProcessing,
    error,
    clearError,
    startRecording,
    stopRecording,
  };
}
