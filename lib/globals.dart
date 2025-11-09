const String GET_ALL_PROMPT = """
Analyze the provided image of a presentation slide. Your task is to extract, identify, and categorize all content on the slide and format it exclusively as a single JSON object.

Do not include any text, apologies, or explanations before or after the JSON code block. Your entire response must be only the valid JSON.

The JSON object must follow this precise structure and adhere to the rules for each key:
{
  "title": ["..."],
  "enumeration": ["...", "..."],
  "equation": ["...", "..."],
  "table": ["...", "..."],
  "image": ["...", "..."],
  "code": ["...", "..."],
  "slide_number": ["..."],
  "summary": ["..."]
}

Core Principle: No Invented Content
Your primary task is to be accurate.
DO NOT INVENT or GUESS content. If an element is not clearly and explicitly visible on the slide, you MUST use an empty array [] for that key.
DO NOT add placeholder text or "N/A". An empty array [] is the only correct way to represent missing content.
This applies to all keys. It is perfectly acceptable and expected to return {"slide_number": [], "equation": [], "table": [], ...} if those elements are not on the slide.


Key-Specific Instructions:
"title": An array containing the verbatim text of the main slide title. (Use [] if no title is present).
"enumeration": An array of strings, where each string is the verbatim text of one bullet point or numbered list item. (Use [] if no lists are present).
"equation": An array of strings, where each string is the verbatim text of one equation found on the slide. (Use [] if no equations are present).
"table": An array of strings. Each string must be a descriptive summary of a table's content and purpose. (Use [] if no tables are present).
Goal: Describe the table for someone who cannot see it.
Bad: "Sales data."
Good: "A table comparing Q1 and Q2 sales revenue across three different regions: North, South, and West, showing total units sold and percentage growth."
"image": An array of strings. Each string must be a descriptive summary of an image's content and its relevance to the slide. (Use [] if no images are present).
Goal: Explain what the image shows and why it's on the slide.
Bad: "Bar chart."
Good: "A bar chart illustrating the sharp decline in monthly user engagement from January to June."
"code": An array of strings. Each string must be a concise summary of what a code block does or represents (e.g., "A Python function that calculates the factorial of a number using recursion"). (Use [] if no code blocks are present).
"slide_number": An array containing the verbatim slide number. If no slide number is visible on the image, you MUST use an empty array []. Do not guess or invent a number.
"summary": An array containing a single string. This string must be a detailed, synthetic summary that explains the entire slide's content and purpose. (Use [] only if the slide is completely blank).
Example: "This slide defines the 'Quantum Entanglement' concept. It begins with a formal definition, lists three key properties of entangled particles, and presents a diagram (the EPR paradox) to visually explain how two particles can remain connected over a distance."

Crucial Rules:
All values must be arrays of strings, even if there is only one item (e.g., "title": ["Main Title"]) or zero items.
If any element is not present on the slide (e.g., there are no tables or equations), you must use an empty array [] for that key.
""";