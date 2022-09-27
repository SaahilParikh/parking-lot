import {useState, useEffect} from 'react';
import AddTaskForm from './components/AddTaskForm.jsx';
import ToDo from './components/ToDo.jsx';

import 'bootstrap/dist/css/bootstrap.min.css';

import './App.css';

function App() {

  const endpoint = 'https://api.saahil.io/items';

  // Tasks (ToDo List) State
  const [toDo, setToDo] = useState([]);

  const refreshTasks = async () => {
    const response = await fetch(endpoint);
    const data = await response.json();
    console.log(data);
    let items = data["Items"];
    setToDo(items);
  }
  
  useEffect(() => {
    refreshTasks();
  }, []); 

  // Temp State
  const [newTask, setNewTask] = useState('');

  // Add task 
  ///////////////////////////
  const addTask = () => {
    if(newTask) {
      let newEntry = { id: newTask }
      fetch(endpoint, {
        method: 'PUT', // *GET, POST, PUT, DELETE, etc.
        mode: 'cors',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(newEntry) // body data type must match "Content-Type" header
      })
      .then(response => response.json())
      .then(data => console.log(data)) // Manipulate the data retrieved back, if we want to do something with it
      .catch(err => console.log(err)) // Do something with the error;
      setToDo([...toDo, newEntry])
      setNewTask('');
    }
  }

  // Delete task 
  ///////////////////////////
  const deleteTask = (id) => {
    console.log(`${endpoint}/${id}`);
    fetch(`${endpoint}/${id}`, {
      method: 'DELETE',
      mode: 'cors'
    })
    .then(res => res.text()) // or res.json()
    .then(res => console.log(res))
    let newTasks = toDo.filter( task => task.id !== id)
    setToDo(newTasks);
  }

  return (
    
    <div className="container App">

    <br /><br />
    <h2>Parking Lot </h2>
    <br /><br />
    
    {
      <AddTaskForm 
        newTask={newTask}
        setNewTask={setNewTask}
        addTask={addTask}
      />
    }

    {/* Display ToDos */}

    {toDo && toDo.length ? '' : 'There\'s nothing in the parking lot...'}

    <ToDo
      toDo={toDo}
      deleteTask={deleteTask}
    /> 

    <br /><br />
    </div>
  );
}

export default App;