const String GEMINI_API_KEY = "AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0";

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

Key-Specific Instructions:
"title": An array containing the verbatim text of the main slide title.
"enumeration": An array of strings, where each string is the verbatim text of one bullet point or numbered list item.
"equation": An array of strings, where each string is the verbatim text of one equation found on the slide.
"table": An array of strings. Each string must be a descriptive summary of a table's content and purpose. Use the table's caption (if present) to inform this summary. Goal: Describe the table for someone who cannot see it. Bad: "Sales data." Good: "A table comparing Q1 and Q2 sales revenue across three different regions: North, South, and West, showing total units sold and percentage growth." Do not transcribe the full table.
"image": An array of strings. Each string must be a descriptive summary of an image's content and its relevance to the slide. Use the image's caption (if present) to inform this summary. Goal: Explain what the image shows and why it's on the slide. Bad: "Bar chart." Good: "A bar chart illustrating the sharp decline in monthly user engagement from January to June."
"code": An array of strings. Each string must be a concise summary of what a code block does or represents (e.g., "A Python function that calculates the factorial of a number using recursion"). Do not transcribe the full code.
"slide_number": An array containing the verbatim slide number, if one is visible.
"summary": An array containing a single string. This string must be a detailed, synthetic summary that explains the entire slide's content, purpose, and how its elements connect, as if describing it to someone who cannot see it. Example: "This slide defines the 'Quantum Entanglement' concept. It begins with a formal definition, lists three key properties of entangled particles, and presents a diagram (the EPR paradox) to visually explain how two particles can remain connected over a distance."

Crucial Rules:
All values must be arrays of strings, even if there is only one item (e.g., "title": ["Main Title"]) or zero items.
If any element is not present on the slide (e.g., there are no tables or equations), you must use an empty array [] for that key.
""";

