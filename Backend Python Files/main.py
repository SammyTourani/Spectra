# [[[cog
# import cog
# cog.outl(f'# -*- coding: utf-8 -*-')
# ]]]
# -*- coding: utf-8 -*-
# [[[end]]]
from fastapi import FastAPI, Request, File, UploadFile, Form, WebSocket, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sentence_transformers import SentenceTransformer, util
from ultralytics import YOLO
import mediapipe as mp
from transformers import pipeline
from PIL import Image
import numpy as np
import math
import easyocr
from gtts import gTTS
import os
import base64
from dotenv import load_dotenv
from openai import OpenAI
import shutil
import cv2
import io
import traceback
import time # Added for unique filenames

# --- Model Configurations ---
print("Loading models...")
start_time = time.time()

try:
    sentance_model = SentenceTransformer('all-MiniLM-L6-v2')
    print(f"SentenceTransformer loaded in {time.time() - start_time:.2f}s")
    st_load_time = time.time()

    # yolo model
    model = YOLO("yolov8l.pt")
    print(f"YOLO loaded in {time.time() - st_load_time:.2f}s")
    yolo_load_time = time.time()

    # depthestimator model
    depth_estimator = pipeline(task="depth-estimation", model="depth-anything/Depth-Anything-V2-Small-hf", device='mps')
    print(f"Depth Estimator loaded in {time.time() - yolo_load_time:.2f}s")
    depth_load_time = time.time()

    # hand tracker model
    mp_hands = mp.solutions.hands
    hands = mp_hands.Hands(static_image_mode=False, # Changed to False for potential video stream processing
                           max_num_hands=2,
                           min_detection_confidence=0.5,
                           min_tracking_confidence=0.5)
    mp_drawing = mp.solutions.drawing_utils
    print(f"Mediapipe Hands loaded in {time.time() - depth_load_time:.2f}s")
    hands_load_time = time.time()

    # EasyOCR reader (initialize only once)
    # Note: Consider specifying the GPU setting for EasyOCR if needed: easyocr.Reader(['en'], gpu=True) # Or False
    ocr_reader = easyocr.Reader(['en'])
    print(f"EasyOCR loaded in {time.time() - hands_load_time:.2f}s")

except Exception as e:
    print(f"Error loading models: {e}")
    print(traceback.format_exc())
    # Exit if models can't load
    exit(1)

print(f"All models loaded successfully in {time.time() - start_time:.2f}s")
# --- End Model Configurations ---

# --- Helper Functions ---
def perform_ocr_and_speak(image: Image.Image, language='en') -> str:
    """Performs OCR on a PIL image and returns the extracted text."""
    try:
        # Convert PIL image to NumPy array (format EasyOCR prefers)
        image_np = np.array(image)
        image_np_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)

        # Perform OCR
        result = ocr_reader.readtext(image_np_bgr)

        # Extract text
        extracted_text = " ".join([text[1] for text in result])
        if not extracted_text:
            return "No text found in the image."
        print("OCR Result:", extracted_text)
        return extracted_text
    except Exception as e:
        print(f"Error during OCR: {e}")
        print(traceback.format_exc())
        return "Error performing text recognition."

def analyze_image_with_gpt(image: Image.Image, api_key: str) -> str:
    """Sends a PIL image to OpenAI GPT-4o for description."""
    try:
        client = OpenAI(api_key=api_key)

        # Convert PIL image to base64
        buffered = io.BytesIO()
        image.save(buffered, format="JPEG") # Save as JPEG for smaller size
        image_data = base64.b64encode(buffered.getvalue()).decode("utf-8")

        prompt = (
            "Describe the main elements of the image in simple, direct language for a visually impaired user. "
            "Focus on key objects, their spatial relationships (e.g., 'a cup is on the table to your left'), and essential features. "
            "Avoid ambiguity and excessive detail. Mention people if present. Keep the description concise (around 5-10 seconds of speech)."
            # "Explain this as if the user is blind or has impaired vision in adequate detail." # Removed redundancy
        )

        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_data}", "detail": "low"}} # Use low detail for faster processing
                    ]
                }
            ],
            max_tokens=150 # Reduced max_tokens for brevity
        )
        description = response.choices[0].message.content
        print("GPT Description:", description)
        return description
    except Exception as e:
        print(f"Error interacting with OpenAI: {e}")
        print(traceback.format_exc())
        return "Error analyzing the image."

def text_to_speech(text: str) -> str | None:
    """Converts text to speech using gTTS and returns base64 encoded audio."""
    if not text or text.startswith("Error"):
        print("Skipping TTS for empty or error text.")
        return None
    try:
        tts = gTTS(text=text, lang='en', slow=False)
        # Use BytesIO instead of writing to disk
        audio_fp = io.BytesIO()
        tts.write_to_fp(audio_fp)
        audio_fp.seek(0) # Rewind the buffer to the beginning

        # Read the audio data and encode it as base64
        audio_data = audio_fp.read()
        audio_base64 = base64.b64encode(audio_data).decode("utf-8")
        print(f"Generated TTS audio ({len(audio_data)} bytes)")
        return audio_base64
    except Exception as e:
        print(f"Error during Text-to-Speech generation: {e}")
        print(traceback.format_exc())
        return None

def hand_to_object_finder(image: Image.Image, query_text: str) -> str:
    """Finds an object relative to the hand in a PIL image based on a text query."""
    try:
        query_embedding = sentance_model.encode(query_text, convert_to_tensor=True)
        target_object_name = '' # Store the name identified by sentence transformer
        directions = ["directly right", "up and right", "directly up", "up and left",
                      "directly left", "down and left", "directly down", "down and right"]

        # Convert PIL image to NumPy array (in BGR format for OpenCV)
        image_np = np.array(image)
        image_np = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
        image_height, image_width = image_np.shape[:2]

        # Convert the BGR image to RGB for Mediapipe and Depth Estimator
        rgb_image = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(rgb_image) # For depth estimator

        # --- Model Processing ---
        hand_results = hands.process(rgb_image)
        yolo_results = model(image_np) # Use BGR image for YOLO if trained on it
        depth_result = depth_estimator(pil_image)
        depth_map = np.array(depth_result['depth'])
        # --- End Model Processing ---

        detected_objects = [] # Store (label, score, box)
        for box in yolo_results[0].boxes:
            class_id = int(box.cls)
            label = model.names[class_id]
            # Skip people
            if label.lower() == 'person':
                continue
            confidence = float(box.conf)
            coords = list(map(int, box.xyxy[0]))
            detected_objects.append({"label": label, "confidence": confidence, "box": coords})

        if not detected_objects:
            return "No objects detected in the scene."

        # Find the object best matching the query using SentenceTransformer
        object_labels = [obj["label"] for obj in detected_objects]
        if not object_labels:
             return "No non-person objects detected." # Handle case after filtering people

        doc_embeddings = sentance_model.encode(object_labels, convert_to_tensor=True)
        cosine_scores = util.cos_sim(query_embedding, doc_embeddings)[0]
        ranked_docs = sorted(zip(cosine_scores.tolist(), detected_objects), reverse=True, key=lambda x: x[0])

        # Check if the best match score is reasonably high
        best_score, best_match_object = ranked_docs[0]
        print(f"Best match: {best_match_object['label']} with score {best_score:.2f}")
        if best_score < 0.3: # Adjust threshold as needed
             return f"I couldn't clearly identify a {query_text}. Objects detected: {', '.join(object_labels)}."

        target_object_name = best_match_object["label"]
        x1, y1, x2, y2 = best_match_object["box"]
        object_center_x = (x1 + x2) // 2
        object_center_y = (y1 + y2) // 2

        if not hand_results.multi_hand_landmarks:
            return f"I see a {target_object_name}, but I don't detect your hand."

        # Assume the first detected hand is the relevant one
        hand_landmarks = hand_results.multi_hand_landmarks[0]

        # Use wrist landmark as hand position
        wrist_landmark = hand_landmarks.landmark[mp_hands.HandLandmark.WRIST]
        # Ensure coordinates are within image bounds
        hand_x = min(max(0, int(wrist_landmark.x * image_width)), image_width - 1)
        hand_y = min(max(0, int(wrist_landmark.y * image_height)), image_height - 1)

        # Calculate direction vector
        dx = object_center_x - hand_x
        dy = object_center_y - hand_y # Y is typically inverted in image coordinates (0 at top)

        # Calculate angle (adjusting for typical image coordinate system)
        angle_radians = math.atan2(-dy, dx) # Negate dy for standard angle calculation

        # Normalize angle to 0 to 2*pi
        # angle_normalized = (angle_radians + 2 * math.pi) % (2 * math.pi)

        # Determine direction index (adjusting segments)
        # Angle ranges (approx): Right(> -pi/8, <= pi/8), UR(> pi/8, <= 3pi/8), etc.
        angle_segment = math.pi / 4 # 45 degrees
        angle_index = round(angle_radians / angle_segment) % 8
        # Map index: 0:R, 1:UR, 2:U, 3:UL, 4:L, 5:DL, 6:D, 7:DR --> becomes -4: L, -3: DL, etc.
        # Correct mapping based on angle ranges and desired output:
        # Example: angle_radians = 0 (Right) -> angle_index = 0 -> directions[0]
        # Example: angle_radians = pi/2 (Up) -> angle_index = 2 -> directions[2]
        # Example: angle_radians = pi (Left) -> angle_index = 4 -> directions[4]
        # Example: angle_radians = -pi/2 (Down) -> angle_index = -2 -> maps to 6 -> directions[6]
        final_angle_index = (int(angle_index) + 8) % 8 # Ensure index is 0-7

        # Depth comparison
        # Ensure depth map coordinates are valid
        object_depth = depth_map[object_center_y, object_center_x]
        hand_depth = depth_map[hand_y, hand_x]
        depth_difference = abs(float(hand_depth) - float(object_depth))

        # Calculate distance in pixels
        pixel_distance = math.sqrt(dx**2 + dy**2)

        print(f"Object='{target_object_name}' Center=({object_center_x},{object_center_y}) Depth={object_depth:.2f}")
        print(f"Hand Wrist=({hand_x},{hand_y}) Depth={hand_depth:.2f}")
        print(f"Pixel Dist={pixel_distance:.1f} Depth Diff={depth_difference:.2f} Angle={math.degrees(angle_radians):.1f} Rad={angle_radians:.2f} Index={final_angle_index}")

        # Refined Logic (adjust thresholds based on testing depth_map values)
        # NOTE: Depth values from 'depth-anything' are relative, not metric. Thresholds need tuning.
        # High depth value usually means closer.
        depth_threshold_far = 80 # Tune this - difference indicating significant distance apart
        depth_threshold_near = 30 # Tune this - difference indicating similar depth
        pixel_distance_threshold_reach = 150 # Tune this

        if depth_difference >= depth_threshold_far and float(hand_depth) < float(object_depth) : # Hand depth < object depth = hand is further
             # Check if the object is significantly further than the hand
             direction_to_move = "forward" # Or adjust based on relative depth
             return f"Move your hand {direction_to_move} towards the {target_object_name}, which is {directions[final_angle_index]} of your hand."
        elif depth_difference <= depth_threshold_near and pixel_distance <= pixel_distance_threshold_reach:
             return f"The {target_object_name} is within reach, {directions[final_angle_index]} of your hand."
        else:
            # Default direction instruction
            return f"The {target_object_name} is {directions[final_angle_index]} of your hand."

    except Exception as e:
        print(f"Error in hand_to_object_finder: {e}")
        print(traceback.format_exc())
        return "Error finding the object relative to your hand."

# --- FastAPI App Setup ---
load_dotenv()
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    print("Warning: OPENAI_API_KEY not found in environment variables.")
# print("DEBUG: OpenAI API Key loaded.") # Keep this commented unless debugging key issues

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Allows all origins for development
    allow_credentials=True,
    allow_methods=["*"], # Allows all methods
    allow_headers=["*"], # Allows all headers
)

# Precompute prompt embeddings for intent classification
prompts = ['Read the text', 'describe what I am viewing', 'Identify object location', 'Other']
try:
    prompt_embeddings = sentance_model.encode(prompts, convert_to_tensor=True)
    print("Prompt embeddings computed.")
except Exception as e:
    print(f"Error computing prompt embeddings: {e}")
    exit(1)
# --- End FastAPI App Setup ---

# --- API Endpoints ---
@app.post("/process")
async def process_request(query: str = Form(...), file: UploadFile | None = File(None)):
    """
    Processes a text query, optionally with an image, determines intent,
    performs the required action, and returns text and audio response.
    """
    print(f"\n--- Received Request ---")
    print(f"Query: '{query}'")
    print(f"File received: {'Yes' if file else 'No'}")
    if file:
        print(f"Filename: {file.filename}, Content-Type: {file.content_type}")

    start_process_time = time.time()
    results_text = ""
    image = None

    try:
        # --- Intent Classification ---
        start_intent_time = time.time()
        query_embedding = sentance_model.encode(query, convert_to_tensor=True)
        cosine_scores = util.cos_sim(query_embedding, prompt_embeddings)[0]
        ranked_docs = sorted(zip(cosine_scores.tolist(), prompts), reverse=True, key=lambda x: x[0])
        score, intent = ranked_docs[0]
        print(f"Intent classified as '{intent}' with score {score:.2f} in {time.time() - start_intent_time:.2f}s")
        # --- End Intent Classification ---

        # --- Image Handling ---
        if file and file.content_type and 'image/' in file.content_type:
            start_image_read_time = time.time()
            contents = await file.read()
            if not contents:
                 print("Error: Uploaded file is empty.")
                 raise HTTPException(status_code=400, detail="Uploaded image file is empty.")
            try:
                image = Image.open(io.BytesIO(contents)).convert("RGB")
                print(f"Image loaded ({image.width}x{image.height}) in {time.time() - start_image_read_time:.2f}s")
            except Exception as img_err:
                print(f"Error opening image: {img_err}")
                raise HTTPException(status_code=400, detail=f"Invalid image file provided. Error: {img_err}")
        elif intent in [prompts[0], prompts[1], prompts[2]]: # Check if image is required but not provided
             print(f"Error: Intent '{intent}' requires an image, but none was provided.")
             raise HTTPException(status_code=400, detail=f"This request ('{intent}') requires an image. Please provide one.")
        # --- End Image Handling ---

        # --- Action Routing ---
        start_action_time = time.time()
        if score <= 0.35: # Confidence threshold for understanding the query
            results_text = "I'm sorry, I couldn't quite understand your request. Could you please rephrase?"
            intent = "Unknown" # Mark intent as unknown
        elif intent == prompts[0]: # Read the text
            results_text = perform_ocr_and_speak(image)
        elif intent == prompts[1]: # Describe what I am viewing
            if not api_key:
                 results_text = "Error: OpenAI API key is not configured on the server."
            else:
                 results_text = analyze_image_with_gpt(image, api_key)
        elif intent == prompts[2]: # Identify object location
            # Extract potential object name from the query for better matching
            # Basic extraction: assume the object is the last part of the query
            # More robust NLP could be used here.
            object_query = query.replace("Identify object location", "").replace("find the", "").replace("where is the", "").strip()
            if not object_query:
                object_query = query # Fallback if simple extraction fails
            print(f"Object query for hand_to_object_finder: '{object_query}'")
            results_text = hand_to_object_finder(image, object_query)
        else: # Other / Fallback
            results_text = "I am not equipped to handle that request. Please try asking something else, like 'read the text', 'describe what I see', or 'find the [object]'."

        print(f"Action '{intent}' completed in {time.time() - start_action_time:.2f}s")
        # --- End Action Routing ---

        # --- TTS Generation ---
        start_tts_time = time.time()
        audio_base64 = text_to_speech(results_text)
        print(f"TTS generation finished in {time.time() - start_tts_time:.2f}s")
        # --- End TTS Generation ---

        # --- Prepare Response ---
        response_data = {
            "recognized_text": results_text,
            "audio_base64": audio_base64
        }
        print(f"--- Request Processed Successfully in {time.time() - start_process_time:.2f}s ---")
        return JSONResponse(content=response_data)
        # --- End Prepare Response ---

    except HTTPException as http_err:
        # Handle client-side errors (like missing image) gracefully
        print(f"HTTP Exception: {http_err.detail}")
        print(f"--- Request Failed (HTTP {http_err.status_code}) ---")
        # Optionally generate TTS for the error message
        error_audio = text_to_speech(http_err.detail)
        return JSONResponse(
            content={"error": http_err.detail, "audio_base64": error_audio},
            status_code=http_err.status_code
        )
    except Exception as e:
        # Handle unexpected server errors
        error_msg = f"An unexpected error occurred: {str(e)}"
        print(error_msg)
        print(traceback.format_exc())
        print(f"--- Request Failed (Internal Server Error) ---")
        # Optionally generate TTS for a generic error message
        error_audio = text_to_speech("Sorry, an internal error occurred.")
        return JSONResponse(
            content={"error": "An internal server error occurred.", "audio_base64": error_audio},
            status_code=500
        )

@app.get("/")
async def root():
    """Root endpoint to check if the server is running."""
    return {"message": "Spectra API is running. Use the /process endpoint."}

# WebSocket endpoint (remains for future use)
@app.websocket("/ws/video-stream")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connection established")
    try:
        while True:
            # Placeholder for receiving video frames or commands
            data = await websocket.receive_text() # Or receive_bytes
            print(f"WebSocket received: {data}")
            # Add logic for processing streamed video/commands here
            await websocket.send_text(f"Message received: {data}")
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        print("WebSocket connection closed")
        await websocket.close()

# --- End API Endpoints ---

# Script execution (for running with `python main.py`)
if __name__ == "__main__":
    import uvicorn
    print("Starting Uvicorn server...")
    # Use 0.0.0.0 to make it accessible on the local network
    # Use reload=True for development, disable for production
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)