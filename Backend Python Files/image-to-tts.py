import cv2
import easyocr
from gtts import gTTS
import os

cap = cv2.VideoCapture(0)

def perform_ocr_and_speak(image_path, language='en', output_file='output.mp3'):
    # Initialize the EasyOCR reader
    reader = easyocr.Reader([language])
    
    # Perform OCR on the image
    result = reader.readtext(image_path)
    
    # Extract text from the result
    extracted_text = " ".join([text[1] for text in result])
    
    print("Extracted Text:", extracted_text)
    
    # Create a gTTS object
    tts = gTTS(text=extracted_text, lang=language, slow=False)
    
    # Save the audio file
    tts.save(output_file)
    
    # Play the audio file
    os.system(f"start {output_file}")

# Check if the camera opened successfully
if not cap.isOpened():
    print("Error: Could not open camera")
else:
    # Capture a single frame
    ret, frame = cap.read()
    if ret:
        # Save the frame as an image
        cv2.imwrite("captured_frame.jpg", frame)
        print("Frame captured and saved as 'captured_frame.jpg'")
    else:
        print("Error: Could not read frame")

# Release the camera
cap.release()

# Example usage
image_path = frame #"C:/Users/user/Desktop/preview-page0.jpg"  # Replace with the path to your image
perform_ocr_and_speak(image_path)


