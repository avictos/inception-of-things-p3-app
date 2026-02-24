const express = require('express')
const app = express()

app.get('/', (req, res) => {
    console.log('Received request for /');
    const response = {
        status: 'ok',
        message: 'v2'
    };
    res.json(response);
})

const PORT = 8888;
app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
