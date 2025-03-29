from fastapi import FastAPI, Request, File, UploadFile
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
import os
from dotenv import load_dotenv
from openai import OpenAI
import shutil
import cv2
from fastapi.responses import JSONResponse
import io


#python -m uvicorn main:app --reload
#python -m uvicorn main:app --host 172.18.51.126 --port 8000
#python -m uvicorn main:app --host 172.18.179.5 --port 8000
sentance_model = SentenceTransformer('all-MiniLM-L6-v2')

# yolo model
model = YOLO("yolov8l.pt") 

#depthestimator model also note to SAMMY if running this from ur computer change device to 'cuda' i only put cpu cuz mine isnt powerful enough
depth_estimator = pipeline(task="depth-estimation", model="depth-anything/Depth-Anything-V2-Small-hf", device='mps')
#SAMMY PLEASE READ THIS ONE COMMENT

# hand tracker model
mp_hands = mp.solutions.hands
hands = mp_hands.Hands(static_image_mode=False,
                       max_num_hands=2,
                       min_detection_confidence=0.5,
                       min_tracking_confidence=0.5)
mp_drawing = mp.solutions.drawing_utils
#model configs done

#functions
def perform_ocr_and_speak(image, language='en'):
    # Convert PIL image to NumPy array
    image_np = np.array(image)
    # Save temporarily to disk for EasyOCR
    temp_path = "temp_image.jpg"
    cv2.imwrite(temp_path, cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR))
    
    # Initialize the EasyOCR reader
    reader = easyocr.Reader([language])
    
    # Perform OCR on the image
    result = reader.readtext(temp_path)
    
    # Extract text from the result
    extracted_text = " ".join([text[1] for text in result])
    
    # Clean up
    os.remove(temp_path)
    
    return extracted_text

def analyze_image_with_gpt(image, api_key):
    client = OpenAI(api_key=api_key)

    # Convert PIL image to base64
    buffered = io.BytesIO()
    image.save(buffered, format="JPEG")
    image_data = base64.b64encode(buffered.getvalue()).decode("utf-8")

    prompt = (
         "Describe the main elements of the image in simple, direct language. "
        "Focus on key objects, their positions, and basic room features. Avoid detailed adjectives. "
        "Mention people if present. Keep the description very brief, suitable for about 5-7 seconds of speech. "
        "Explain this as if the user is blind or has impaired vision in adequate detail."
    )

    try:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_data}"}}
                    ]
                }
            ],
            max_tokens=300
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {str(e)}"

def text_to_speech(text):
    # Convert text to speech using gTTS
    tts = gTTS(text=text, lang='en')
    audio_path = "output_audio.mp3"
    tts.save(audio_path)
    
    # Read the audio file and encode it as base64
    with open(audio_path, "rb") as audio_file:
        audio_data = audio_file.read()
        audio_base64 = base64.b64encode(audio_data).decode("utf-8")
    
    # Clean up the audio file
    os.remove(audio_path)
    
    return audio_base64

#handsfunction
def hand_to_object_finder(image, query_embedding):
    name = ''
    directions = ["Right", "Up-Right", "Up", "Up-Left",
                  "Left", "Down-Left", "Down", "Down-Right"]

    # Convert PIL image to NumPy array (in BGR format for OpenCV)
    image_np = np.array(image)
    image_np = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)

    # Convert the image to RGB for Mediapipe
    rgb_image = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
    pil_image = Image.fromarray(rgb_image)

    # Run Mediapipe Hands on the image
    hand_results = hands.process(rgb_image)

    # Run YOLO model on the image
    yolo_results = model(image_np)

    # Run depth-estimation model on the image
    depth_result = depth_estimator(pil_image)
    depth_map = np.array(depth_result['depth'])  # Extract the depth map (as a NumPy array)

    # Normalize the depth map for visualization (scale to 0-255)
    normalized_depth = cv2.normalize(depth_map, None, 0, 255, cv2.NORM_MINMAX).astype('uint8')
    depth_colored = cv2.applyColorMap(normalized_depth, cv2.COLORMAP_MAGMA)  # Colorize for better visualization

    c = 0
    things = []
    x1s, y1s, x2s, y2s = 0, 0, 0, 0

    # Draw YOLO detections
    for box in yolo_results[0].boxes:
        class_id = int(box.cls)
        label = model.names[class_id]

        # Skip people count
        if class_id == 0:
            c += 1
            continue

        # Get box coordinates
        x1, y1, x2, y2 = map(int, box.xyxy[0])  # Bounding box coordinates
        if name == label:
            x1s, y1s, x2s, y2s = x1, y1, x2, y2

        # Draw bounding box
        cv2.rectangle(image_np, (x1, y1), (x2, y2), (0, 255, 0), 2)

        # Put label text
        text = f"{label}"
        cv2.putText(image_np, text, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
        things.append(model.names[class_id])

    # Calculate vector for direction
    if things:
        doc_embeddings = sentance_model.encode(things, convert_to_tensor=True)
        cosine_scores = util.cos_sim(query_embedding, doc_embeddings)[0]
        ranked_docs = sorted(zip(cosine_scores.tolist(), things), reverse=True, key=lambda x: x[0])
        score, name = ranked_docs[0]
    object_x = (x1s + x2s) // 2
    object_y = (y1s + y2s) // 2

    # Process hands
    if hand_results.multi_hand_landmarks:
        for hand_landmarks in hand_results.multi_hand_landmarks:
            mp_drawing.draw_landmarks(
                image_np,
                hand_landmarks,
                mp_hands.HAND_CONNECTIONS,
                mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2),
                mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2, circle_radius=2),
            )
    if hand_results.multi_hand_landmarks and len(yolo_results[0].boxes) - c != 0:
        hand_landmarks = hand_results.multi_hand_landmarks[0]
        hand_x = int(hand_landmarks.landmark[mp_hands.HandLandmark.WRIST].x * image_np.shape[1])
        hand_y = int(hand_landmarks.landmark[mp_hands.HandLandmark.WRIST].y * image_np.shape[0])
        dx = object_x - hand_x
        dy = object_y - hand_y
        angle_radians = math.atan2(dy, dx)
        angle_radians = (angle_radians + math.pi) % (2 * math.pi) - math.pi
        angleindex = round((angle_radians + math.pi) / (math.pi / 4)) % 8
        dist = math.sqrt((object_x - hand_x) ** 2 + (object_y - hand_y) ** 2)
        obd, handd = depth_map[object_y, object_x], depth_map[hand_y, hand_x]
        if abs(int(handd) - int(obd)) >= 80:
            return 'go forward'
        elif (abs(int(handd) - int(obd)) <= 30) and dist <= 150:
            return 'object within reach'
        else:
            return directions[angleindex]
    return "No hand or object detected."



load_dotenv()
api_key = os.getenv("OPENAI_API_KEY")
print("DEBUG: OpenAI API Key =", api_key)

app = FastAPI()
prompts = ['Read the text', 'describe what I am viewing', 'Identify object location', 'Other']
doc_embeddings = sentance_model.encode(prompts, convert_to_tensor=True)
response_toapp = ''
query_embedding_chatbot = None  # Initialize as None

#server requests
@app.post("/speech")
async def receive_speech(request: Request):
    global response_toapp, query_embedding_chatbot  # Use global variables
    data = await request.json()
    recognized_text = data.get("query")
    query_embedding_chatbot = sentance_model.encode(recognized_text, convert_to_tensor=True)
    cosine_scores = util.cos_sim(query_embedding_chatbot, doc_embeddings)[0] 
    ranked_docs = sorted(zip(cosine_scores.tolist(), prompts), reverse=True, key=lambda x: x[0])
    score, name = ranked_docs[0]
    if score <= 0.35:
        response_toapp = "I'm Sorry I could not understand"
    elif name == prompts[0]:
        response_toapp = 'Ok, I will begin reading the text, please point your camera towards it'
    elif name == prompts[1]:
        response_toapp = 'Ok, I will describe what is in front of you'
    elif name == prompts[2]:
        response_toapp = 'Ok, locating the object'
    elif name == prompts[3]:
        response_toapp = 'I am not equipped to answer that please try asking a different question'
    print("Received from Swift:", recognized_text)
    # ...use recognized_text to trigger your YOLO, Mediapipe, etc.
    return (response_toapp)

@app.post("/process-image")
async def process_image(file: UploadFile = File(...)):
    global response_toapp, query_embedding_chatbot  # Use global variables
    try:
        # Read the uploaded image file
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")

        # Debug: Print the value of response_toapp
        print("DEBUG: response_toapp =", response_toapp)

        # Process the image (example: OCR pipeline)
        if response_toapp == 'Ok, I will begin reading the text, please point your camera towards it':
            results = perform_ocr_and_speak(image)
        elif response_toapp == 'Ok, I will describe what is in front of you':
            results = analyze_image_with_gpt(image, api_key)
        elif response_toapp == 'Ok, locating the object':
            if query_embedding_chatbot is None:
                results = "Error: Please provide the object to locate via the /speech endpoint first."
            else:
                results = hand_to_object_finder(image, query_embedding_chatbot)
        else:
            results = "Invalid action specified."
        
        # Extract the text (you can modify based on your task)
        recognized_text = results

        print("Recognized Text:", recognized_text)

        # Convert the recognized text to speech and get base64-encoded audio
        audio_base64 = text_to_speech(recognized_text)

        # Return the recognized text and audio as a response
        return JSONResponse(content={
            "recognized_text": recognized_text,
            "audio_base64": audio_base64
        })

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)